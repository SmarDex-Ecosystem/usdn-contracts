// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { LibBitmap } from "solady/src/utils/LibBitmap.sol";
import { FixedPointMathLib } from "solady/src/utils/FixedPointMathLib.sol";

import { IUsdnProtocolActions } from "src/interfaces/UsdnProtocol/IUsdnProtocolActions.sol";
import {
    Position,
    ProtocolAction,
    PendingAction,
    DepositPendingAction,
    WithdrawalPendingAction,
    LongPendingAction,
    LiquidationsEffects,
    PreviousActionsData,
    PositionId,
    TickData
} from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import { UsdnProtocolLong } from "src/UsdnProtocol/UsdnProtocolLong.sol";
import { PriceInfo } from "src/interfaces/OracleMiddleware/IOracleMiddlewareTypes.sol";
import { IUsdn } from "src/interfaces/Usdn/IUsdn.sol";
import { TickMath } from "src/libraries/TickMath.sol";
import { SignedMath } from "src/libraries/SignedMath.sol";
import { HugeUint } from "src/libraries/HugeUint.sol";
import { console2 } from "forge-std/Test.sol";

abstract contract UsdnProtocolActions is IUsdnProtocolActions, UsdnProtocolLong {
    using SafeERC20 for IERC20Metadata;
    using SafeERC20 for IUsdn;
    using SafeCast for uint256;
    using SafeCast for int256;
    using LibBitmap for LibBitmap.Bitmap;
    using SignedMath for int256;
    using HugeUint for HugeUint.Uint512;

    /**
     * @dev Structure to hold the transient data during `_initiateWithdrawal`
     * @param pendingActionPrice The adjusted price with position fees applied
     * @param totalExpo The current total expo
     * @param balanceLong The current long balance
     * @param balanceVault The vault balance, adjusted according to the pendingActionPrice
     * @param usdn The USDN token
     * @param isLiquidationPending Whether some ticks are still populated above the current price (left to liquidate)
     */
    struct WithdrawalData {
        uint128 pendingActionPrice;
        uint256 totalExpo;
        uint256 balanceLong;
        uint256 balanceVault;
        IUsdn usdn;
        bool isLiquidationPending;
    }

    /**
     * @dev Structure to hold the transient data during `_initiateOpenPosition`
     * @param adjustedPrice The adjusted price with position fees applied
     * @param posId The new position id
     * @param liquidationPenalty The liquidation penalty
     * @param positionTotalExpo The total expo of the position
     * @param isLiquidationPending Whether some ticks are still populated above the current price (left to liquidate)
     */
    struct InitiateOpenPositionData {
        uint128 adjustedPrice;
        PositionId posId;
        uint8 liquidationPenalty;
        uint128 positionTotalExpo;
        bool isLiquidationPending;
    }

    /**
     * @dev Structure to hold the transient data during `_validateOpenPosition`
     * @param action The long pending action
     * @param startPrice The new entry price of the position
     * @param tickHash The tick hash
     * @param pos The position object
     * @param liqPriceWithoutPenalty The new liquidation price without penalty
     * @param leverage The new leverage
     * @param liquidationPenalty The liquidation penalty for the position's tick
     * @param isLiquidationPending Whether some ticks are still populated above the current price (left to liquidate)
     */
    struct ValidateOpenPositionData {
        LongPendingAction action;
        uint128 startPrice;
        bytes32 tickHash;
        Position pos;
        uint128 liqPriceWithoutPenalty;
        uint128 leverage;
        uint8 liquidationPenalty;
        bool isLiquidationPending;
    }

    /**
     * @dev Structure to hold the transient data during `_initiateClosePosition`
     * @param pos The position to close
     * @param liquidationPenalty The liquidation penalty
     * @param totalExpoToClose The total expo to close
     * @param lastPrice The price after the last balances update
     * @param tempPositionValue The bounded value of the position that was removed from the long balance
     * @param longTradingExpo The long trading expo
     * @param liqMulAcc The liquidation multiplier accumulator
     * @param isLiquidationPending Whether some ticks are still populated above the current price (left to liquidate)
     */
    struct ClosePositionData {
        Position pos;
        uint8 liquidationPenalty;
        uint128 totalExpoToClose;
        uint128 lastPrice;
        uint256 tempPositionValue;
        uint256 longTradingExpo;
        HugeUint.Uint512 liqMulAcc;
        bool isLiquidationPending;
    }

    /// @inheritdoc IUsdnProtocolActions
    uint256 public constant MIN_USDN_SUPPLY = 1000;

    /// @inheritdoc IUsdnProtocolActions
    function initiateDeposit(
        uint128 amount,
        bytes calldata currentPriceData,
        PreviousActionsData calldata previousActionsData,
        address to
    ) external payable initializedAndNonReentrant {
        uint64 securityDepositValue = _securityDepositValue;
        if (msg.value < securityDepositValue) {
            revert UsdnProtocolSecurityDepositTooLow();
        }
        uint256 balanceBefore = address(this).balance;

        (uint256 amountToRefund, bool isLiquidationPending) =
            _initiateDeposit(msg.sender, to, amount, securityDepositValue, currentPriceData);

        if (!isLiquidationPending) {
            unchecked {
                amountToRefund += _executePendingActionOrRevert(previousActionsData);
            }
        }

        _refundExcessEther(securityDepositValue, amountToRefund, balanceBefore);
        _checkPendingFee();
    }

    /// @inheritdoc IUsdnProtocolActions
    function validateDeposit(bytes calldata depositPriceData, PreviousActionsData calldata previousActionsData)
        external
        payable
        initializedAndNonReentrant
    {
        uint256 balanceBefore = address(this).balance;

        (uint256 amountToRefund, bool isLiquidationPending) = _validateDeposit(msg.sender, depositPriceData);

        if (!isLiquidationPending) {
            unchecked {
                amountToRefund += _executePendingActionOrRevert(previousActionsData);
            }
        }

        _refundExcessEther(0, amountToRefund, balanceBefore);
        _checkPendingFee();
    }

    /// @inheritdoc IUsdnProtocolActions
    function initiateWithdrawal(
        uint152 usdnShares,
        bytes calldata currentPriceData,
        PreviousActionsData calldata previousActionsData,
        address to
    ) external payable initializedAndNonReentrant {
        uint64 securityDepositValue = _securityDepositValue;
        if (msg.value < securityDepositValue) {
            revert UsdnProtocolSecurityDepositTooLow();
        }

        uint256 balanceBefore = address(this).balance;

        (uint256 amountToRefund, bool isLiquidationPending) =
            _initiateWithdrawal(msg.sender, to, usdnShares, securityDepositValue, currentPriceData);

        if (!isLiquidationPending) {
            unchecked {
                amountToRefund += _executePendingActionOrRevert(previousActionsData);
            }
        }

        _refundExcessEther(securityDepositValue, amountToRefund, balanceBefore);
        _checkPendingFee();
    }

    /// @inheritdoc IUsdnProtocolActions
    function validateWithdrawal(bytes calldata withdrawalPriceData, PreviousActionsData calldata previousActionsData)
        external
        payable
        initializedAndNonReentrant
    {
        uint256 balanceBefore = address(this).balance;

        (uint256 amountToRefund, bool isLiquidationPending) = _validateWithdrawal(msg.sender, withdrawalPriceData);

        if (!isLiquidationPending) {
            unchecked {
                amountToRefund += _executePendingActionOrRevert(previousActionsData);
            }
        }

        _refundExcessEther(0, amountToRefund, balanceBefore);
        _checkPendingFee();
    }

    /// @inheritdoc IUsdnProtocolActions
    function initiateOpenPosition(
        uint128 amount,
        uint128 desiredLiqPrice,
        bytes calldata currentPriceData,
        PreviousActionsData calldata previousActionsData,
        address to
    ) external payable initializedAndNonReentrant returns (PositionId memory posId_) {
        uint64 securityDepositValue = _securityDepositValue;
        if (msg.value < securityDepositValue) {
            revert UsdnProtocolSecurityDepositTooLow();
        }

        uint256 balanceBefore = address(this).balance;
        uint256 amountToRefund;
        bool isLiquidationPending;

        (posId_, amountToRefund, isLiquidationPending) =
            _initiateOpenPosition(msg.sender, to, amount, desiredLiqPrice, securityDepositValue, currentPriceData);

        if (!isLiquidationPending) {
            unchecked {
                amountToRefund += _executePendingActionOrRevert(previousActionsData);
            }
        }
        _refundExcessEther(securityDepositValue, amountToRefund, balanceBefore);
        _checkPendingFee();
    }

    /// @inheritdoc IUsdnProtocolActions
    function validateOpenPosition(bytes calldata openPriceData, PreviousActionsData calldata previousActionsData)
        external
        payable
        initializedAndNonReentrant
    {
        uint256 balanceBefore = address(this).balance;

        (uint256 amountToRefund, bool isLiquidationPending) = _validateOpenPosition(msg.sender, openPriceData);

        if (!isLiquidationPending) {
            unchecked {
                amountToRefund += _executePendingActionOrRevert(previousActionsData);
            }
        }

        _refundExcessEther(0, amountToRefund, balanceBefore);
        _checkPendingFee();
    }

    /// @inheritdoc IUsdnProtocolActions
    function initiateClosePosition(
        PositionId calldata posId,
        uint128 amountToClose,
        bytes calldata currentPriceData,
        PreviousActionsData calldata previousActionsData,
        address to
    ) external payable initializedAndNonReentrant {
        uint64 securityDepositValue = _securityDepositValue;
        if (msg.value < securityDepositValue) {
            revert UsdnProtocolSecurityDepositTooLow();
        }

        uint256 balanceBefore = address(this).balance;

        (uint256 amountToRefund, bool isLiquidationPending) =
            _initiateClosePosition(msg.sender, to, posId, amountToClose, securityDepositValue, currentPriceData);

        if (!isLiquidationPending) {
            unchecked {
                amountToRefund += _executePendingActionOrRevert(previousActionsData);
            }
        }

        _refundExcessEther(securityDepositValue, amountToRefund, balanceBefore);
        _checkPendingFee();
    }

    /// @inheritdoc IUsdnProtocolActions
    function validateClosePosition(bytes calldata closePriceData, PreviousActionsData calldata previousActionsData)
        external
        payable
        initializedAndNonReentrant
    {
        uint256 balanceBefore = address(this).balance;

        (uint256 amountToRefund, bool isLiquidationPending) = _validateClosePosition(msg.sender, closePriceData);

        if (!isLiquidationPending) {
            unchecked {
                amountToRefund += _executePendingActionOrRevert(previousActionsData);
            }
        }

        _refundExcessEther(0, amountToRefund, balanceBefore);
        _checkPendingFee();
    }

    /// @inheritdoc IUsdnProtocolActions
    function liquidate(bytes calldata currentPriceData, uint16 iterations)
        external
        payable
        initializedAndNonReentrant
        returns (uint256 liquidatedPositions_)
    {
        uint256 balanceBefore = address(this).balance;
        PriceInfo memory currentPrice = _getOraclePrice(ProtocolAction.Liquidation, 0, currentPriceData);

        (liquidatedPositions_,) = _applyPnlAndFundingAndLiquidate(
            currentPrice.neutralPrice, currentPrice.timestamp, iterations, true, currentPriceData
        );

        _refundExcessEther(0, 0, balanceBefore);
        _checkPendingFee();
    }

    /// @inheritdoc IUsdnProtocolActions
    function validateActionablePendingActions(PreviousActionsData calldata previousActionsData, uint256 maxValidations)
        external
        payable
        initializedAndNonReentrant
        returns (uint256 validatedActions_)
    {
        if (_lastPrice < getEffectivePriceForTick(_highestPopulatedTick)) {
            revert UsdnProtocolLiquidationPending();
        }

        uint256 balanceBefore = address(this).balance;
        uint256 amountToRefund;

        if (maxValidations > previousActionsData.rawIndices.length) {
            maxValidations = previousActionsData.rawIndices.length;
        }
        do {
            (, bool executed, uint256 securityDepositValue) = _executePendingAction(previousActionsData);
            if (!executed) {
                break;
            }
            unchecked {
                validatedActions_++;
                amountToRefund += securityDepositValue;
            }
        } while (validatedActions_ < maxValidations);
        _refundExcessEther(0, amountToRefund, balanceBefore);
        _checkPendingFee();
    }

    /**
     * @notice The deposit vault imbalance limit state verification
     * @dev To ensure that the protocol does not imbalance more than
     * the deposit limit on vault side, otherwise revert
     * @param depositValue the deposit value in asset
     */
    function _checkImbalanceLimitDeposit(uint256 depositValue) internal view {
        int256 depositExpoImbalanceLimitBps = _depositExpoImbalanceLimitBps;

        // early return in case limit is disabled
        if (depositExpoImbalanceLimitBps == 0) {
            return;
        }

        int256 currentLongExpo = _totalExpo.toInt256().safeSub(_balanceLong.toInt256());

        // cannot be calculated
        if (currentLongExpo == 0) {
            revert UsdnProtocolInvalidLongExpo();
        }

        int256 imbalanceBps = ((_balanceVault + depositValue).toInt256().safeSub(currentLongExpo)).safeMul(
            int256(BPS_DIVISOR)
        ).safeDiv(currentLongExpo);

        if (imbalanceBps >= depositExpoImbalanceLimitBps) {
            revert UsdnProtocolImbalanceLimitReached(imbalanceBps);
        }
    }

    /**
     * @notice The withdrawal imbalance limit state verification
     * @dev To ensure that the protocol does not imbalance more than
     * the withdrawal limit on long side, otherwise revert
     * @param withdrawalValue The withdrawal value in asset
     * @param totalExpo The current total expo
     */
    function _checkImbalanceLimitWithdrawal(uint256 withdrawalValue, uint256 totalExpo) internal view {
        int256 withdrawalExpoImbalanceLimitBps = _withdrawalExpoImbalanceLimitBps;

        // early return in case limit is disabled
        if (withdrawalExpoImbalanceLimitBps == 0) {
            return;
        }

        int256 newVaultExpo = _balanceVault.toInt256().safeSub(withdrawalValue.toInt256());

        // cannot be calculated if equal zero
        if (newVaultExpo == 0) {
            revert UsdnProtocolInvalidVaultExpo();
        }

        int256 imbalanceBps = ((totalExpo.toInt256().safeSub(_balanceLong.toInt256())).safeSub(newVaultExpo)).safeMul(
            int256(BPS_DIVISOR)
        ).safeDiv(newVaultExpo);

        if (imbalanceBps >= withdrawalExpoImbalanceLimitBps) {
            revert UsdnProtocolImbalanceLimitReached(imbalanceBps);
        }
    }

    /**
     * @notice The open long imbalance limit state verification. Revert
     * @dev To ensure that the protocol does not imbalance more than
     * the open limit on long side, otherwise revert
     * @param openTotalExpoValue The open position expo value
     * @param openCollatValue The open position collateral value
     */
    function _checkImbalanceLimitOpen(uint256 openTotalExpoValue, uint256 openCollatValue) internal view {
        int256 openExpoImbalanceLimitBps = _openExpoImbalanceLimitBps;

        // early return in case limit is disabled
        if (openExpoImbalanceLimitBps == 0) {
            return;
        }

        int256 currentVaultExpo = _balanceVault.toInt256();

        // cannot be calculated if equal zero
        if (currentVaultExpo == 0) {
            revert UsdnProtocolInvalidVaultExpo();
        }

        int256 imbalanceBps = (
            ((_totalExpo + openTotalExpoValue).toInt256().safeSub((_balanceLong + openCollatValue).toInt256())).safeSub(
                currentVaultExpo
            )
        ).safeMul(int256(BPS_DIVISOR)).safeDiv(currentVaultExpo);

        if (imbalanceBps >= openExpoImbalanceLimitBps) {
            revert UsdnProtocolImbalanceLimitReached(imbalanceBps);
        }
    }

    /**
     * @notice The close vault imbalance limit state verification
     * @dev To ensure that the protocol does not imbalance more than
     * the close limit on vault side, otherwise revert
     * @param closePosTotalExpoValue The close position total expo value
     * @param closeCollatValue The close position collateral value
     */
    function _checkImbalanceLimitClose(uint256 closePosTotalExpoValue, uint256 closeCollatValue) internal view {
        int256 closeExpoImbalanceLimitBps = _closeExpoImbalanceLimitBps;

        // early return in case limit is disabled
        if (closeExpoImbalanceLimitBps == 0) {
            return;
        }

        int256 newLongExpo = (_totalExpo.toInt256().safeSub(closePosTotalExpoValue.toInt256())).safeSub(
            _balanceLong.toInt256().safeSub(closeCollatValue.toInt256())
        );

        // cannot be calculated if equal or lower than zero
        if (newLongExpo <= 0) {
            revert UsdnProtocolInvalidLongExpo();
        }

        int256 imbalanceBps =
            (_balanceVault.toInt256().safeSub(newLongExpo)).safeMul(int256(BPS_DIVISOR)).safeDiv(newLongExpo);

        if (imbalanceBps >= closeExpoImbalanceLimitBps) {
            revert UsdnProtocolImbalanceLimitReached(imbalanceBps);
        }
    }

    /**
     * @notice Send rewards to the liquidator.
     * @dev Should still emit an event if liquidationRewards = 0 to better keep track of those anomalies as rewards for
     * those will be managed off-chain.
     * @param liquidatedTicks The number of ticks that were liquidated.
     * @param remainingCollateral The amount of collateral remaining after liquidations.
     * @param rebased Whether a USDN rebase was performed.
     * @param priceData The price oracle update data.
     */
    function _sendRewardsToLiquidator(
        uint16 liquidatedTicks,
        int256 remainingCollateral,
        bool rebased,
        bytes memory priceData
    ) internal {
        // Get how much we should give to the liquidator as rewards
        uint256 liquidationRewards =
            _liquidationRewardsManager.getLiquidationRewards(liquidatedTicks, remainingCollateral, rebased, priceData);

        // Avoid underflows in situation of extreme bad debt
        if (_balanceVault < liquidationRewards) {
            liquidationRewards = _balanceVault;
        }

        // Update the vault's balance
        unchecked {
            _balanceVault -= liquidationRewards;
        }

        // Transfer rewards (wsteth) to the liquidator
        _asset.safeTransfer(msg.sender, liquidationRewards);

        emit LiquidatorRewarded(msg.sender, liquidationRewards);
    }

    /**
     * @notice Initiate a deposit of assets into the vault to mint USDN.
     * @dev Consult the current oracle middleware implementation to know the expected format for the price data, using
     * the `ProtocolAction.InitiateDeposit` action.
     * The price validation might require payment according to the return value of the `getValidationCost` function
     * of the middleware.
     * @param user The address of the user initiating the deposit.
     * @param to The address to receive the USDN tokens.
     * @param amount The amount of wstETH to deposit.
     * @param securityDepositValue The value of the security deposit for the newly created pending action
     * @param currentPriceData The current price data
     * @return amountToRefund_ If there are pending liquidations we'll refund the securityDepositValue,
     * else we'll only refund the security deposit value of the stale pending action
     * @return isLiquidationPending_ If there are pending position to liquidate
     */
    function _initiateDeposit(
        address user,
        address to,
        uint128 amount,
        uint64 securityDepositValue,
        bytes calldata currentPriceData
    ) internal returns (uint256 amountToRefund_, bool isLiquidationPending_) {
        if (to == address(0)) {
            revert UsdnProtocolInvalidAddressTo();
        }
        if (amount == 0) {
            revert UsdnProtocolZeroAmount();
        }

        PriceInfo memory currentPrice =
            _getOraclePrice(ProtocolAction.InitiateDeposit, block.timestamp, currentPriceData);

        (, isLiquidationPending_) = _applyPnlAndFundingAndLiquidate(
            currentPrice.neutralPrice, currentPrice.timestamp, _liquidationIteration, false, currentPriceData
        );

        _checkImbalanceLimitDeposit(amount);

        // Apply fees on price
        uint128 pendingActionPrice =
            (currentPrice.price - currentPrice.price * _positionFeeBps / BPS_DIVISOR).toUint128();

        DepositPendingAction memory pendingAction = DepositPendingAction({
            action: ProtocolAction.ValidateDeposit,
            timestamp: uint40(block.timestamp),
            user: user,
            to: to,
            securityDepositValue: securityDepositValue,
            _unused: 0,
            amount: amount,
            assetPrice: pendingActionPrice,
            totalExpo: _totalExpo,
            balanceVault: _vaultAssetAvailable(_totalExpo, _balanceVault, _balanceLong, pendingActionPrice, _lastPrice)
                .toUint256(),
            balanceLong: _balanceLong,
            usdnTotalSupply: _usdn.totalSupply()
        });

        amountToRefund_ = _addPendingAction(user, _convertDepositPendingAction(pendingAction), isLiquidationPending_);

        // Case there are still pending liquidations
        if (isLiquidationPending_) {
            return (amountToRefund_ + securityDepositValue, true);
        }

        // Calculate the amount of SDEX tokens to burn
        uint256 usdnToMintEstimated = _calcMintUsdn(
            pendingAction.amount, pendingAction.balanceVault, pendingAction.usdnTotalSupply, pendingAction.assetPrice
        );
        uint32 burnRatio = _sdexBurnOnDepositRatio;
        uint256 sdexToBurn = _calcSdexToBurn(usdnToMintEstimated, burnRatio);
        // We want to at least mint 1 wei of USDN
        if (usdnToMintEstimated == 0) {
            revert UsdnProtocolDepositTooSmall();
        }
        // We want to at least burn 1 wei of SDEX if SDEX burning is enabled
        if (burnRatio != 0 && sdexToBurn == 0) {
            revert UsdnProtocolDepositTooSmall();
        }
        if (sdexToBurn > 0) {
            // Send SDEX to the dead address
            _sdex.safeTransferFrom(user, DEAD_ADDRESS, sdexToBurn);
        }

        // Transfer assets
        _asset.safeTransferFrom(user, address(this), amount);

        emit InitiatedDeposit(user, to, amount, block.timestamp);
    }

    function _validateDeposit(address user, bytes calldata priceData)
        internal
        returns (uint256 securityDepositValue_, bool isLiquidationPending_)
    {
        (PendingAction memory pending, uint128 rawIndex) = _getPendingActionOrRevert(user);

        // check type of action
        if (pending.action != ProtocolAction.ValidateDeposit) {
            revert UsdnProtocolInvalidPendingAction();
        }
        // sanity check
        if (pending.user != user) {
            revert UsdnProtocolInvalidPendingAction();
        }

        isLiquidationPending_ = _validateDepositWithAction(pending, priceData);

        if (!isLiquidationPending_) {
            _clearPendingAction(user, rawIndex);
            return (pending.securityDepositValue, false);
        }
    }

    function _validateDepositWithAction(PendingAction memory pending, bytes calldata priceData)
        internal
        returns (bool isLiquidationPending_)
    {
        DepositPendingAction memory deposit = _toDepositPendingAction(pending);

        PriceInfo memory currentPrice = _getOraclePrice(ProtocolAction.ValidateDeposit, deposit.timestamp, priceData);

        // adjust balances
        (, isLiquidationPending_) = _applyPnlAndFundingAndLiquidate(
            currentPrice.neutralPrice, currentPrice.timestamp, _liquidationIteration, false, priceData
        );

        // early return in case there are still pending liquidations
        if (isLiquidationPending_) {
            return true;
        }

        // We calculate the amount of USDN to mint, either considering the asset price at the time of the initiate
        // action, or the current price provided for validation. We will use the lower of the two amounts to mint.
        // Apply fees on price
        uint128 priceWithFees = (currentPrice.price - (currentPrice.price * _positionFeeBps) / BPS_DIVISOR).toUint128();

        uint256 usdnToMint1 =
            _calcMintUsdn(deposit.amount, deposit.balanceVault, deposit.usdnTotalSupply, deposit.assetPrice);

        uint256 usdnToMint2 = _calcMintUsdn(
            deposit.amount,
            // Calculate the available balance in the vault side if the price moves to `priceWithFees`
            _vaultAssetAvailable(
                deposit.totalExpo, deposit.balanceVault, deposit.balanceLong, priceWithFees, deposit.assetPrice
            ).toUint256(),
            deposit.usdnTotalSupply,
            priceWithFees
        );

        uint256 usdnToMint;
        // We use the lower of the two amounts to mint
        if (usdnToMint1 <= usdnToMint2) {
            usdnToMint = usdnToMint1;
        } else {
            usdnToMint = usdnToMint2;
        }

        _balanceVault += deposit.amount;

        _usdn.mint(deposit.to, usdnToMint);
        emit ValidatedDeposit(deposit.user, deposit.to, deposit.amount, usdnToMint, deposit.timestamp);
    }

    /**
     * @notice Update protocol balances, then prepare the data for the withdrawal action.
     * @dev Reverts if the imbalance limit is reached.
     * @param usdnShares The amount of USDN shares to burn.
     * @param currentPriceData The current price data
     * @return data_ The withdrawal data struct
     */
    function _prepareWithdrawalData(uint152 usdnShares, bytes calldata currentPriceData)
        internal
        returns (WithdrawalData memory data_)
    {
        PriceInfo memory currentPrice =
            _getOraclePrice(ProtocolAction.InitiateWithdrawal, block.timestamp, currentPriceData);

        (, data_.isLiquidationPending) = _applyPnlAndFundingAndLiquidate(
            currentPrice.neutralPrice, currentPrice.timestamp, _liquidationIteration, false, currentPriceData
        );

        // Apply fees on price
        data_.pendingActionPrice = (currentPrice.price + currentPrice.price * _positionFeeBps / BPS_DIVISOR).toUint128();

        data_.totalExpo = _totalExpo;
        data_.balanceLong = _balanceLong;
        data_.balanceVault = _vaultAssetAvailable(
            data_.totalExpo, _balanceVault, data_.balanceLong, data_.pendingActionPrice, _lastPrice
        ).toUint256();
        data_.usdn = _usdn;

        _checkImbalanceLimitWithdrawal(
            FixedPointMathLib.fullMulDiv(usdnShares, data_.balanceVault, data_.usdn.totalShares()), data_.totalExpo
        );
    }

    /**
     * @notice Prepare the pending action struct for a withdrawal and add it to the queue
     * @param user The address of the user initiating the withdrawal
     * @param to The address that will receive the assets
     * @param usdnShares The amount of USDN shares to burn
     * @param securityDepositValue The value of the security deposit for the newly created pending action
     * @param data The withdrawal action data
     * @return amountToRefund_ Refund The security deposit value of a stale pending action
     */
    function _createWithdrawalPendingAction(
        address user,
        address to,
        uint152 usdnShares,
        uint64 securityDepositValue,
        WithdrawalData memory data
    ) internal returns (uint256 amountToRefund_) {
        PendingAction memory action = _convertWithdrawalPendingAction(
            WithdrawalPendingAction({
                action: ProtocolAction.ValidateWithdrawal,
                timestamp: uint40(block.timestamp),
                user: user,
                to: to,
                securityDepositValue: securityDepositValue,
                sharesLSB: _calcWithdrawalAmountLSB(usdnShares),
                sharesMSB: _calcWithdrawalAmountMSB(usdnShares),
                assetPrice: data.pendingActionPrice,
                totalExpo: data.totalExpo,
                balanceVault: data.balanceVault,
                balanceLong: data.balanceLong,
                usdnTotalShares: data.usdn.totalShares()
            })
        );

        amountToRefund_ = _addPendingAction(user, action, data.isLiquidationPending);
    }

    /**
     * @notice Initiate a withdrawal of assets from the vault by providing USDN tokens.
     * @dev Consult the current oracle middleware implementation to know the expected format for the price data, using
     * the `ProtocolAction.InitiateWithdrawal` action.
     * The price validation might require payment according to the return value of the `getValidationCost` function
     * of the middleware.
     * @param user The address of the user initiating the withdrawal.
     * @param to The address that will receive the assets
     * @param usdnShares The amount of USDN shares to burn.
     * @param securityDepositValue The value of the security deposit for the newly created pending action
     * @param currentPriceData The current price data
     * @return amountToRefund_ If there are pending liquidations we'll refund the securityDepositValue,
     * else we'll only refund the security deposit value of the stale pending action
     * @return isLiquidationPending_ If there are pending position to liquidate
     */
    function _initiateWithdrawal(
        address user,
        address to,
        uint152 usdnShares,
        uint64 securityDepositValue,
        bytes calldata currentPriceData
    ) internal returns (uint256 amountToRefund_, bool isLiquidationPending_) {
        if (to == address(0)) {
            revert UsdnProtocolInvalidAddressTo();
        }
        if (usdnShares == 0) {
            revert UsdnProtocolZeroAmount();
        }

        WithdrawalData memory data = _prepareWithdrawalData(usdnShares, currentPriceData);
        console2.log("data.isLiquidationPending", data.isLiquidationPending);

        amountToRefund_ = _createWithdrawalPendingAction(user, to, usdnShares, securityDepositValue, data);

        console2.log("data.isLiquidationPending", data.isLiquidationPending);

        // Case there are still pending liquidations
        if (data.isLiquidationPending) {
            return (amountToRefund_ + securityDepositValue, true);
        }

        // retrieve the USDN tokens, checks that balance is sufficient
        data.usdn.transferSharesFrom(user, address(this), usdnShares);

        emit InitiatedWithdrawal(user, to, data.usdn.convertToTokens(usdnShares), block.timestamp);
    }

    function _validateWithdrawal(address user, bytes calldata priceData)
        internal
        returns (uint256 securityDepositValue_, bool isLiquidationPending_)
    {
        (PendingAction memory pending, uint128 rawIndex) = _getPendingActionOrRevert(user);

        // check type of action
        if (pending.action != ProtocolAction.ValidateWithdrawal) {
            revert UsdnProtocolInvalidPendingAction();
        }
        // sanity check
        if (pending.user != user) {
            revert UsdnProtocolInvalidPendingAction();
        }

        isLiquidationPending_ = _validateWithdrawalWithAction(pending, priceData);

        if (!isLiquidationPending_) {
            _clearPendingAction(user, rawIndex);
            return (pending.securityDepositValue, false);
        }
    }

    function _validateWithdrawalWithAction(PendingAction memory pending, bytes calldata priceData)
        internal
        returns (bool isLiquidationPending_)
    {
        WithdrawalPendingAction memory withdrawal = _toWithdrawalPendingAction(pending);

        PriceInfo memory currentPrice =
            _getOraclePrice(ProtocolAction.ValidateWithdrawal, withdrawal.timestamp, priceData);

        (, isLiquidationPending_) = _applyPnlAndFundingAndLiquidate(
            currentPrice.neutralPrice, currentPrice.timestamp, _liquidationIteration, false, priceData
        );

        // early return in case there are still pending liquidations
        if (isLiquidationPending_) {
            return true;
        }

        // Apply fees on price
        uint128 withdrawalPriceWithFees =
            (currentPrice.price + (currentPrice.price * _positionFeeBps) / BPS_DIVISOR).toUint128();

        // We calculate the available balance of the vault side, either considering the asset price at the time of the
        // initiate action, or the current price provided for validation. We will use the lower of the two amounts to
        // redeem the underlying asset share.
        uint256 available1 = withdrawal.balanceVault;
        uint256 available2 = _vaultAssetAvailable(
            withdrawal.totalExpo,
            withdrawal.balanceVault,
            withdrawal.balanceLong,
            withdrawalPriceWithFees,
            withdrawal.assetPrice
        ).toUint256();
        uint256 available;
        if (available1 <= available2) {
            available = available1;
        } else {
            available = available2;
        }

        uint256 shares = _mergeWithdrawalAmountParts(withdrawal.sharesLSB, withdrawal.sharesMSB);

        // we have the USDN in the contract already
        IUsdn usdn = _usdn;

        uint256 assetToTransfer = _calcBurnUsdn(shares, available, usdn.totalShares());

        usdn.burnShares(shares);

        // send the asset to the user
        if (assetToTransfer > 0) {
            _balanceVault -= assetToTransfer;
            _asset.safeTransfer(withdrawal.to, assetToTransfer);
        }

        emit ValidatedWithdrawal(
            withdrawal.user, withdrawal.to, assetToTransfer, usdn.convertToTokens(shares), withdrawal.timestamp
        );
    }

    /**
     * @notice Update protocol balances, then prepare the data for the initiate open position action
     * @dev Reverts if the imbalance limit is reached, or if the safety margin is not respected
     * @param amount The amount of wstETH to deposit
     * @param desiredLiqPrice The desired liquidation price, including the liquidation penalty
     * @param currentPriceData The current price data
     * @return data_ The temporary data for the open position action
     */
    function _prepareInitiateOpenPositionData(uint128 amount, uint128 desiredLiqPrice, bytes calldata currentPriceData)
        internal
        returns (InitiateOpenPositionData memory data_)
    {
        PriceInfo memory currentPrice =
            _getOraclePrice(ProtocolAction.InitiateOpenPosition, block.timestamp, currentPriceData);
        data_.adjustedPrice = (currentPrice.price + (currentPrice.price * _positionFeeBps) / BPS_DIVISOR).toUint128();

        uint128 neutralPrice = currentPrice.neutralPrice.toUint128();

        (, data_.isLiquidationPending) = _applyPnlAndFundingAndLiquidate(
            neutralPrice, currentPrice.timestamp, _liquidationIteration, false, currentPriceData
        );

        // we calculate the closest valid tick down for the desired liq price with liquidation penalty
        data_.posId.tick = getEffectiveTickForPrice(desiredLiqPrice);
        data_.liquidationPenalty = getTickLiquidationPenalty(data_.posId.tick);

        // Calculate effective liquidation price
        uint128 liqPrice = getEffectivePriceForTick(data_.posId.tick);

        // Liquidation price must be at least x% below current price
        _checkSafetyMargin(neutralPrice, liqPrice);

        // remove liquidation penalty for leverage and total expo calculations
        uint128 liqPriceWithoutPenalty =
            getEffectivePriceForTick(_calcTickWithoutPenalty(data_.posId.tick, data_.liquidationPenalty));
        _checkOpenPositionLeverage(data_.adjustedPrice, liqPriceWithoutPenalty);

        data_.positionTotalExpo = _calculatePositionTotalExpo(amount, data_.adjustedPrice, liqPriceWithoutPenalty);
        _checkImbalanceLimitOpen(data_.positionTotalExpo, amount);
    }

    /**
     * @notice Prepare the pending action struct for an open position and add it to the queue.
     * @param user The address of the user initiating the open position.
     * @param to The address that will be the owner of the position
     * @param securityDepositValue The value of the security deposit for the newly created pending action
     * @param data The open position action data
     * @return amountToRefund_ Refund The security deposit value of a stale pending action
     */
    function _createOpenPendingAction(
        address user,
        address to,
        uint64 securityDepositValue,
        InitiateOpenPositionData memory data
    ) internal returns (uint256 amountToRefund_) {
        LongPendingAction memory action = LongPendingAction({
            action: ProtocolAction.ValidateOpenPosition,
            timestamp: uint40(block.timestamp),
            user: user,
            to: to,
            securityDepositValue: securityDepositValue,
            tick: data.posId.tick,
            closeAmount: 0,
            closePosTotalExpo: 0,
            tickVersion: data.posId.tickVersion,
            index: data.posId.index,
            closeLiqMultiplier: 0,
            closeBoundedPositionValue: 0
        });

        amountToRefund_ = _addPendingAction(user, _convertLongPendingAction(action), data.isLiquidationPending);
    }

    /**
     * @notice Initiate an open position action.
     * @dev Consult the current oracle middleware implementation to know the expected format for the price data, using
     * the `ProtocolAction.InitiateOpenPosition` action.
     * The price validation might require payment according to the return value of the `getValidationCost` function
     * of the middleware.
     * The position is immediately included in the protocol calculations with a temporary entry price (and thus
     * leverage). The validation operation then updates the entry price and leverage with fresher data.
     * @param user The address of the user initiating the open position.
     * @param to The address that will be the owner of the position
     * @param amount The amount of wstETH to deposit.
     * @param desiredLiqPrice The desired liquidation price, including the liquidation penalty.
     * @param securityDepositValue The value of the security deposit for the newly created pending action
     * @param currentPriceData  The current price data (used to calculate the temporary leverage and entry price,
     * pending validation)
     * @return posId_ The unique index of the opened position
     * @return amountToRefund_ If there are pending liquidations we'll refund the securityDepositValue,
     * else we'll only refund the security deposit value of the stale pending action
     * @return isLiquidationPending_ If there are pending position to liquidate
     */
    function _initiateOpenPosition(
        address user,
        address to,
        uint128 amount,
        uint128 desiredLiqPrice,
        uint64 securityDepositValue,
        bytes calldata currentPriceData
    ) internal returns (PositionId memory posId_, uint256 amountToRefund_, bool isLiquidationPending_) {
        if (to == address(0)) {
            revert UsdnProtocolInvalidAddressTo();
        }
        if (amount == 0) {
            revert UsdnProtocolZeroAmount();
        }
        if (amount < _minLongPosition) {
            revert UsdnProtocolLongPositionTooSmall();
        }

        InitiateOpenPositionData memory data =
            _prepareInitiateOpenPositionData(amount, desiredLiqPrice, currentPriceData);

        // Register position and adjust contract state
        Position memory long = Position({
            user: to,
            amount: amount,
            totalExpo: data.positionTotalExpo,
            timestamp: uint40(block.timestamp)
        });
        (data.posId.tickVersion, data.posId.index) = _saveNewPosition(data.posId.tick, long, data.liquidationPenalty);
        _balanceLong += long.amount;
        posId_ = data.posId;

        amountToRefund_ = _createOpenPendingAction(user, to, securityDepositValue, data);

        // Case there are still pending liquidations
        if (data.isLiquidationPending) {
            PositionId memory emptyPosId;
            return (emptyPosId, amountToRefund_ + securityDepositValue, true);
        }

        _asset.safeTransferFrom(user, address(this), amount);

        emit InitiatedOpenPosition(
            user, to, uint40(block.timestamp), data.positionTotalExpo, amount, data.adjustedPrice, posId_
        );
    }

    function _validateOpenPosition(address user, bytes calldata priceData)
        internal
        returns (uint256 securityDepositValue_, bool isLiquidationPending_)
    {
        (PendingAction memory pending, uint128 rawIndex) = _getPendingActionOrRevert(user);

        // check type of action
        if (pending.action != ProtocolAction.ValidateOpenPosition) {
            revert UsdnProtocolInvalidPendingAction();
        }
        // sanity check
        if (pending.user != user) {
            revert UsdnProtocolInvalidPendingAction();
        }

        isLiquidationPending_ = _validateOpenPositionWithAction(pending, priceData);

        if (!isLiquidationPending_) {
            _clearPendingAction(user, rawIndex);
            return (pending.securityDepositValue, false);
        }
    }

    /**
     * @notice Update protocol balances, then prepare the data for the validate open position action.
     * @param pending The pending action data
     * @param priceData The current price data
     * @return data_ The validate open position data struct
     * @return liq_ Whether the position was liquidated and the caller should return early
     */
    function _prepareValidateOpenPositionData(PendingAction memory pending, bytes calldata priceData)
        internal
        returns (ValidateOpenPositionData memory data_, bool liq_)
    {
        data_.action = _toLongPendingAction(pending);
        PriceInfo memory currentPrice =
            _getOraclePrice(ProtocolAction.ValidateOpenPosition, data_.action.timestamp, priceData);
        // Apply fees on price
        data_.startPrice = (currentPrice.price + (currentPrice.price * _positionFeeBps) / BPS_DIVISOR).toUint128();

        (, data_.isLiquidationPending) = _applyPnlAndFundingAndLiquidate(
            currentPrice.neutralPrice, currentPrice.timestamp, _liquidationIteration, false, priceData
        );

        uint256 version;
        (data_.tickHash, version) = _tickHash(data_.action.tick);
        if (version != data_.action.tickVersion) {
            // The current tick version doesn't match the version from the pending action.
            // This means the position has been liquidated in the mean time
            emit StalePendingActionRemoved(
                data_.action.user,
                PositionId({ tick: data_.action.tick, tickVersion: data_.action.tickVersion, index: data_.action.index })
            );
            return (data_, true);
        }
        // Get the position
        data_.pos = _longPositions[data_.tickHash][data_.action.index];
        // Re-calculate leverage
        data_.liquidationPenalty = _tickData[data_.tickHash].liquidationPenalty;
        data_.liqPriceWithoutPenalty =
            getEffectivePriceForTick(_calcTickWithoutPenalty(data_.action.tick, data_.liquidationPenalty));
        // reverts if liqPriceWithoutPenalty >= startPrice
        data_.leverage = _getLeverage(data_.startPrice, data_.liqPriceWithoutPenalty);
    }

    /**
     * @notice Validate an open position action.
     * @param pending The pending action data
     * @param priceData The current price data
     */
    function _validateOpenPositionWithAction(PendingAction memory pending, bytes calldata priceData)
        internal
        returns (bool isLiquidationPending_)
    {
        (ValidateOpenPositionData memory data, bool liquidated) = _prepareValidateOpenPositionData(pending, priceData);

        if (liquidated) {
            return isLiquidationPending_;
        }

        if (data.isLiquidationPending) {
            return true;
        }

        // Leverage is always greater than 1 (liquidationPrice is positive).
        // Even if it drops below _minLeverage between the initiate and validate actions, we still allow it.
        // However, if the leverage exceeds max leverage, then we adjust the liquidation price (tick) to have a leverage
        // of _maxLeverage
        uint128 maxLeverage = uint128(_maxLeverage);
        if (data.leverage > maxLeverage) {
            // theoretical liquidation price for _maxLeverage
            data.liqPriceWithoutPenalty = _getLiquidationPrice(data.startPrice, maxLeverage);
            // adjust to closest valid tick down
            int24 tickWithoutPenalty = getEffectiveTickForPrice(data.liqPriceWithoutPenalty);

            // apply liquidation penalty with the current penalty setting
            uint8 currentLiqPenalty = _liquidationPenalty;
            PositionId memory newPosId;
            newPosId.tick = tickWithoutPenalty + int24(uint24(currentLiqPenalty)) * _tickSpacing;
            // retrieve the actual penalty for this tick we want to use
            uint8 liquidationPenalty = getTickLiquidationPenalty(newPosId.tick);
            // check if the penalty for that tick is different from the current setting
            if (liquidationPenalty == currentLiqPenalty) {
                // Since the tick's penalty is the same as what we assumed, we can use the `tickWithoutPenalty` from
                // above.
                // Retrieve exact liquidation price without penalty
                data.liqPriceWithoutPenalty = getEffectivePriceForTick(tickWithoutPenalty);
            } else {
                // The tick's imposed penalty is different from the current setting, so the `tickWithoutPenalty` we
                // calculated above can't be used to calculate the leverage.
                // We must instead use the tick's penalty to find the new `liqPriceWithoutPenalty` and calculate the
                // leverage.

                // Note: In case the tick liquidation penalty is lower than the current setting, it might lead to a
                // leverage that exceeds the max leverage slightly. We allow this behavior in this rare occurrence.

                // Retrieve exact liquidation price without penalty.
                data.liqPriceWithoutPenalty =
                    getEffectivePriceForTick(_calcTickWithoutPenalty(newPosId.tick, liquidationPenalty));
            }

            // move the position to its new tick, updating its total expo, and returning the new tickVersion and index
            // remove position from old tick completely
            _removeAmountFromPosition(
                data.action.tick, data.action.index, data.pos, data.pos.amount, data.pos.totalExpo
            );
            // update position total expo (because of new leverage / liq price)
            data.pos.totalExpo =
                _calculatePositionTotalExpo(data.pos.amount, data.startPrice, data.liqPriceWithoutPenalty);
            // insert position into new tick
            (newPosId.tickVersion, newPosId.index) = _saveNewPosition(newPosId.tick, data.pos, liquidationPenalty);
            // no long balance update is necessary (collateral didn't change)

            // emit LiquidationPriceUpdated
            emit LiquidationPriceUpdated(
                PositionId({ tick: data.action.tick, tickVersion: data.action.tickVersion, index: data.action.index }),
                newPosId
            );
            emit ValidatedOpenPosition(data.action.user, data.action.to, data.pos.totalExpo, data.startPrice, newPosId);
            return false;
        }

        // Calculate the new total expo
        uint128 expoBefore = data.pos.totalExpo;
        uint128 expoAfter = _calculatePositionTotalExpo(data.pos.amount, data.startPrice, data.liqPriceWithoutPenalty);

        // Update the total expo of the position
        _longPositions[data.tickHash][data.action.index].totalExpo = expoAfter;
        // Update the total expo by adding the position's new expo and removing the old one.
        // Do not use += or it will underflow
        _totalExpo = _totalExpo + expoAfter - expoBefore;

        // update the tick data and the liqMultiplierAccumulator
        {
            TickData storage tickData = _tickData[data.tickHash];
            uint256 unadjustedTickPrice =
                TickMath.getPriceAtTick(data.action.tick - int24(uint24(data.liquidationPenalty)) * _tickSpacing);
            tickData.totalExpo = tickData.totalExpo + expoAfter - expoBefore;
            _liqMultiplierAccumulator = _liqMultiplierAccumulator.add(HugeUint.wrap(expoAfter * unadjustedTickPrice))
                .sub(HugeUint.wrap(expoBefore * unadjustedTickPrice));
        }

        emit ValidatedOpenPosition(
            data.action.user,
            data.action.to,
            expoAfter,
            data.startPrice,
            PositionId({ tick: data.action.tick, tickVersion: data.action.tickVersion, index: data.action.index })
        );
    }

    /**
     * @notice Perform checks for the initiate close position action.
     * @dev Reverts if the position is not owned by the user, the amount to close is higher than the position amount, or
     * the amount to close is zero.
     * @param user The address of the user initiating the close position.
     * @param to The address that will receive the assets
     * @param amountToClose The amount of collateral to remove from the position's amount
     * @param pos The position to close
     */
    function _checkInitiateClosePosition(address user, address to, uint128 amountToClose, Position memory pos)
        internal
        view
    {
        if (pos.user != user) {
            revert UsdnProtocolUnauthorized();
        }

        if (amountToClose > pos.amount) {
            revert UsdnProtocolAmountToCloseHigherThanPositionAmount(amountToClose, pos.amount);
        }

        // Make sure the remaining position is higher than _minLongPosition
        uint128 remainingAmount = pos.amount - amountToClose;
        if (remainingAmount > 0 && remainingAmount < _minLongPosition) {
            revert UsdnProtocolLongPositionTooSmall();
        }

        if (amountToClose == 0) {
            revert UsdnProtocolAmountToCloseIsZero();
        }

        if (to == address(0)) {
            revert UsdnProtocolInvalidAddressTo();
        }
    }

    /**
     * @notice Update protocol balances, then prepare the data for the initiate close position action
     * @dev Reverts if the imbalance limit is reached, or if any of the checks in `_checkInitiateClosePosition` fail
     * Returns without creating a pending action if the position gets liquidated in this transaction
     * @param user The address of the user initiating the close position
     * @param to The address that will receive the assets
     * @param posId The unique identifier of the position
     * @param amountToClose The amount of collateral to remove from the position's amount
     * @param currentPriceData The current price data
     * @return data_ The close position data
     * @return liq_ Whether the position was liquidated and the caller should return early
     */
    function _prepareClosePositionData(
        address user,
        address to,
        PositionId memory posId,
        uint128 amountToClose,
        bytes calldata currentPriceData
    ) internal returns (ClosePositionData memory data_, bool liq_) {
        (data_.pos, data_.liquidationPenalty) = getLongPosition(posId);

        _checkInitiateClosePosition(user, to, amountToClose, data_.pos);

        PriceInfo memory currentPrice =
            _getOraclePrice(ProtocolAction.InitiateClosePosition, block.timestamp, currentPriceData);

        (, data_.isLiquidationPending) = _applyPnlAndFundingAndLiquidate(
            currentPrice.neutralPrice, currentPrice.timestamp, _liquidationIteration, false, currentPriceData
        );

        (, uint256 version) = _tickHash(posId.tick);
        if (version != posId.tickVersion) {
            // The current tick version doesn't match the version from the position,
            // that means that the position has been liquidated in this transaction.
            return (data_, true);
        }

        data_.totalExpoToClose = (uint256(data_.pos.totalExpo) * amountToClose / data_.pos.amount).toUint128();

        _checkImbalanceLimitClose(data_.totalExpoToClose, amountToClose);

        data_.longTradingExpo = _totalExpo - _balanceLong;
        data_.liqMulAcc = _liqMultiplierAccumulator;
        data_.lastPrice = _lastPrice;

        // The approximate value position to remove is calculated with `_lastPrice`, so not taking into account
        // any fees. This way, the removal of the position doesn't affect the liquidation multiplier calculations.

        // In order to have the maximum precision, we do not pre-compute the liquidation multiplier with a fixed
        // precision just now, we will store it in the pending action later, to be used in the validate action.
        data_.tempPositionValue = _assetToRemove(
            data_.lastPrice,
            getEffectivePriceForTick(
                _calcTickWithoutPenalty(posId.tick, data_.liquidationPenalty),
                data_.lastPrice,
                data_.longTradingExpo,
                data_.liqMulAcc
            ),
            data_.totalExpoToClose
        );
    }

    /**
     * @notice Prepare the pending action struct for the close position action and add it to the queue.
     * @param user The address of the user initiating the close position.
     * @param to The address that will receive the assets
     * @param posId The unique identifier of the position
     * @param amountToClose The amount of collateral to remove from the position's amount
     * @param securityDepositValue The value of the security deposit for the newly created pending action
     * @param data The close position data
     * @return amountToRefund_ Refund The security deposit value of a stale pending action
     */
    function _createClosePendingAction(
        address user,
        address to,
        PositionId memory posId,
        uint128 amountToClose,
        uint64 securityDepositValue,
        ClosePositionData memory data
    ) internal returns (uint256 amountToRefund_) {
        LongPendingAction memory action = LongPendingAction({
            action: ProtocolAction.ValidateClosePosition,
            timestamp: uint40(block.timestamp),
            user: user,
            to: to,
            securityDepositValue: securityDepositValue,
            tick: posId.tick,
            closeAmount: amountToClose,
            closePosTotalExpo: data.totalExpoToClose,
            tickVersion: posId.tickVersion,
            index: posId.index,
            closeLiqMultiplier: _calcFixedPrecisionMultiplier(data.lastPrice, data.longTradingExpo, data.liqMulAcc),
            closeBoundedPositionValue: data.tempPositionValue
        });

        amountToRefund_ = _addPendingAction(user, _convertLongPendingAction(action), data.isLiquidationPending);
    }

    /**
     * @notice Initiate a close position action.
     * @dev Consult the current oracle middleware implementation to know the expected format for the price data, using
     * the `ProtocolAction.InitiateClosePosition` action.
     * The price validation might require payment according to the return value of the `getValidationCost` function
     * of the middleware.
     * If the current tick version is greater than the tick version of the position (when it was opened), then the
     * position has been liquidated and this function will return 0.
     * The position is taken out of the tick and put in a pending state during this operation. Thus, calculations don't
     * consider this position anymore. The exit price (and thus profit) is not yet set definitively, and will be done
     * during the validate action.
     * @param user The address of the user initiating the close position.
     * @param to The address that will receive the assets
     * @param posId The unique identifier of the position
     * @param amountToClose The amount of collateral to remove from the position's amount
     * @param securityDepositValue The value of the security deposit for the newly created pending action
     * @param currentPriceData The current price data
     * @return amountToRefund_ If there are pending liquidations we'll refund the securityDepositValue,
     * else we'll only refund the security deposit value of the stale pending action
     * @return isLiquidationPending_ If there are pending position to liquidate
     */
    function _initiateClosePosition(
        address user,
        address to,
        PositionId memory posId,
        uint128 amountToClose,
        uint64 securityDepositValue,
        bytes calldata currentPriceData
    ) internal returns (uint256 amountToRefund_, bool isLiquidationPending_) {
        (ClosePositionData memory data, bool liq) =
            _prepareClosePositionData(user, to, posId, amountToClose, currentPriceData);
        if (liq) {
            // position was liquidated in this transaction
            return (0, data.isLiquidationPending);
        }

        amountToRefund_ = _createClosePendingAction(user, to, posId, amountToClose, securityDepositValue, data);

        if (data.isLiquidationPending) {
            return (amountToRefund_ + securityDepositValue, true);
        }

        _balanceLong -= data.tempPositionValue;

        _removeAmountFromPosition(posId.tick, posId.index, data.pos, amountToClose, data.totalExpoToClose);

        emit InitiatedClosePosition(
            user, to, posId, data.pos.amount, amountToClose, data.pos.totalExpo - data.totalExpoToClose
        );
    }

    function _validateClosePosition(address user, bytes calldata priceData)
        internal
        returns (uint256 securityDepositValue_, bool isLiquidationPending_)
    {
        (PendingAction memory pending, uint128 rawIndex) = _getPendingActionOrRevert(user);

        // check type of action
        if (pending.action != ProtocolAction.ValidateClosePosition) {
            revert UsdnProtocolInvalidPendingAction();
        }
        // sanity check
        if (pending.user != user) {
            revert UsdnProtocolInvalidPendingAction();
        }

        isLiquidationPending_ = _validateClosePositionWithAction(pending, priceData);

        if (!isLiquidationPending_) {
            _clearPendingAction(user, rawIndex);
            return (pending.securityDepositValue, false);
        }
    }

    function _validateClosePositionWithAction(PendingAction memory pending, bytes calldata priceData)
        internal
        returns (bool isLiquidationPending_)
    {
        LongPendingAction memory long = _toLongPendingAction(pending);

        PriceInfo memory currentPrice = _getOraclePrice(ProtocolAction.ValidateClosePosition, long.timestamp, priceData);

        (, isLiquidationPending_) = _applyPnlAndFundingAndLiquidate(
            currentPrice.neutralPrice, currentPrice.timestamp, _liquidationIteration, false, priceData
        );

        // early return in case there are still pending liquidations
        if (isLiquidationPending_) {
            return true;
        }

        // Apply fees on price
        uint128 priceWithFees = (currentPrice.price - (currentPrice.price * _positionFeeBps) / BPS_DIVISOR).toUint128();

        // get liquidation price (with liq penalty) to check if position was valid at `timestamp + validationDelay`
        uint128 liquidationPrice = _getEffectivePriceForTick(long.tick, long.closeLiqMultiplier);

        if (currentPrice.neutralPrice <= liquidationPrice) {
            // Position should be liquidated, we don't transfer assets to the user.
            // Position was already removed from tick so no additional bookkeeping is necessary.
            // Credit the full amount to the vault to preserve the total balance invariant.
            _balanceVault += long.closeBoundedPositionValue;
            emit LiquidatedPosition(
                long.user,
                PositionId({ tick: long.tick, tickVersion: long.tickVersion, index: long.index }),
                currentPrice.neutralPrice,
                liquidationPrice
            );
            return false;
        }

        int256 positionValue = _positionValue(
            priceWithFees,
            _getEffectivePriceForTick(
                _calcTickWithoutPenalty(long.tick, getTickLiquidationPenalty(long.tick)), long.closeLiqMultiplier
            ),
            long.closePosTotalExpo
        );
        uint256 assetToTransfer;
        if (positionValue > 0) {
            assetToTransfer = uint256(positionValue);
            // Normally, the position value should be smaller than `long.closeBoundedPositionValue` (due to the position
            // fee).
            // We can send the difference (any remaining collateral) to the vault.
            // If the price increased since the initiate, it's possible that the position value is higher than the
            // `long.closeBoundedPositionValue`. In that case, we need to take the missing assets from the vault.
            if (assetToTransfer < long.closeBoundedPositionValue) {
                uint256 remainingCollateral;
                unchecked {
                    // since assetToTransfer is strictly smaller than closeBoundedPositionValue, this operation can't
                    // underflow
                    remainingCollateral = long.closeBoundedPositionValue - assetToTransfer;
                }
                _balanceVault += remainingCollateral;
            } else if (assetToTransfer > long.closeBoundedPositionValue) {
                uint256 missingValue;
                unchecked {
                    // since assetToTransfer is strictly larger than closeBoundedPositionValue, this operation can't
                    // underflow
                    missingValue = assetToTransfer - long.closeBoundedPositionValue;
                }
                uint256 balanceVault = _balanceVault;
                // If the vault does not have enough balance left to pay out the missing value, we take what we can
                if (missingValue > balanceVault) {
                    _balanceVault = 0;
                    unchecked {
                        // since missingValue is strictly larger than balanceVault, their subtraction can't underflow
                        // moreover, since (missingValue - balanceVault) is smaller than or equal to missingValue,
                        // and since missingValue is smaller than or equal to assetToTransfer,
                        // (missingValue - balanceVault) is smaller than or equal to assetToTransfer, and their
                        // subtraction can't underflow.
                        assetToTransfer -= missingValue - balanceVault;
                    }
                } else {
                    unchecked {
                        // since missingValue is smaller than or equal to balanceVault, this operation can't underflow
                        _balanceVault = balanceVault - missingValue;
                    }
                }
            }
        }
        // in case the position value is zero or negative, we don't transfer any asset to the user

        // send the asset to the user
        if (assetToTransfer > 0) {
            _asset.safeTransfer(long.to, assetToTransfer);
        }

        emit ValidatedClosePosition(
            long.user,
            long.to,
            PositionId({ tick: long.tick, tickVersion: long.tickVersion, index: long.index }),
            assetToTransfer,
            assetToTransfer.toInt256() - _toInt256(long.closeAmount)
        );
    }

    /**
     * @notice Reverts if the position's leverage is higher than max or lower than min
     * @param adjustedPrice The adjusted price of the asset
     * @param liqPriceWithoutPenalty The liquidation price of the position without the liquidation penalty
     */
    function _checkOpenPositionLeverage(uint128 adjustedPrice, uint128 liqPriceWithoutPenalty) internal view {
        // calculate position leverage
        // reverts if liquidationPrice >= entryPrice
        uint128 leverage = _getLeverage(adjustedPrice, liqPriceWithoutPenalty);
        if (leverage < _minLeverage) {
            revert UsdnProtocolLeverageTooLow();
        }
        if (leverage > _maxLeverage) {
            revert UsdnProtocolLeverageTooHigh();
        }
    }

    /**
     * @notice Calculate how much wstETH must be removed from the long balance due to a position closing.
     * @dev The amount is bound by the amount of wstETH available in the long side.
     * @param priceWithFees The current price of the asset, adjusted with fees
     * @param liqPriceWithoutPenalty The liquidation price without penalty
     * @param posExpo The total expo of the position
     * @return boundedPosValue_ The amount of assets to remove from the long balance, bound by zero and the available
     * long balance
     */
    function _assetToRemove(uint128 priceWithFees, uint128 liqPriceWithoutPenalty, uint128 posExpo)
        internal
        view
        returns (uint256 boundedPosValue_)
    {
        // The available amount of asset on the long side (with the current balance)
        uint256 available = _balanceLong;

        // Calculate position value
        int256 positionValue = _positionValue(priceWithFees, liqPriceWithoutPenalty, posExpo);

        if (positionValue <= 0) {
            // should not happen, unless we did not manage to liquidate all ticks that needed to be liquidated during
            // the initiateClosePosition
            boundedPosValue_ = 0;
        } else if (uint256(positionValue) > available) {
            boundedPosValue_ = available;
        } else {
            boundedPosValue_ = uint256(positionValue);
        }
    }

    /**
     * @notice Execute the first actionable pending action or revert if the price data was not provided.
     * @param data The price data and raw indices
     * @return securityDepositValue_ The security deposit value of the executed action
     */
    function _executePendingActionOrRevert(PreviousActionsData calldata data)
        internal
        returns (uint256 securityDepositValue_)
    {
        bool success;
        (success,, securityDepositValue_) = _executePendingAction(data);
        if (!success) {
            revert UsdnProtocolInvalidPendingActionData();
        }
    }

    /**
     * @notice Execute the first actionable pending action and report success.
     * @param data The price data and raw indices
     * @return success_ Whether the price data is valid
     * @return executed_ Whether the pending action was executed (false if the queue has no actionable item)
     * @return securityDepositValue_ The security deposit value of the executed action
     */
    function _executePendingAction(PreviousActionsData calldata data)
        internal
        returns (bool success_, bool executed_, uint256 securityDepositValue_)
    {
        (PendingAction memory pending, uint128 rawIndex) = _getActionablePendingAction();
        if (pending.action == ProtocolAction.None) {
            // no pending action
            return (true, false, 0);
        }
        uint256 length = data.priceData.length;
        if (data.rawIndices.length != length || length < 1) {
            return (false, false, 0);
        }
        uint128 offset;
        unchecked {
            // underflow is desired here (wrap-around)
            offset = rawIndex - data.rawIndices[0];
        }
        if (offset >= length || data.rawIndices[offset] != rawIndex) {
            return (false, false, 0);
        }
        bytes calldata priceData = data.priceData[offset];
        _clearPendingAction(pending.user, rawIndex);
        if (pending.action == ProtocolAction.ValidateDeposit) {
            _validateDepositWithAction(pending, priceData);
        } else if (pending.action == ProtocolAction.ValidateWithdrawal) {
            _validateWithdrawalWithAction(pending, priceData);
        } else if (pending.action == ProtocolAction.ValidateOpenPosition) {
            _validateOpenPositionWithAction(pending, priceData);
        } else if (pending.action == ProtocolAction.ValidateClosePosition) {
            _validateClosePositionWithAction(pending, priceData);
        }
        success_ = true;
        executed_ = true;
        securityDepositValue_ = pending.securityDepositValue;
        emit SecurityDepositRefunded(pending.user, msg.sender, securityDepositValue_);
    }

    function _getOraclePrice(ProtocolAction action, uint256 timestamp, bytes calldata priceData)
        internal
        returns (PriceInfo memory price_)
    {
        uint256 validationCost = _oracleMiddleware.validationCost(priceData, action);
        if (address(this).balance < validationCost) {
            revert UsdnProtocolInsufficientOracleFee();
        }
        price_ = _oracleMiddleware.parseAndValidatePrice{ value: validationCost }(uint128(timestamp), action, priceData);
    }

    /**
     * @notice Applies PnL, funding, and liquidates positions if necessary.
     * @param neutralPrice The neutral price for the asset.
     * @param timestamp The timestamp at which the operation is performed.
     * @param iterations The number of iterations for the liquidation process.
     * @param ignoreInterval A boolean indicating whether to ignore the interval for USDN rebase.
     * @param priceData The price oracle update data.
     * @return liquidatedPositions_ The number of positions that were liquidated.
     * @return isLiquidationPending_ If there are pending position to liquidate
     * @dev If there were any liquidated positions, it sends rewards to the msg.sender.
     */
    function _applyPnlAndFundingAndLiquidate(
        uint256 neutralPrice,
        uint256 timestamp,
        uint16 iterations,
        bool ignoreInterval,
        bytes calldata priceData
    ) internal returns (uint256 liquidatedPositions_, bool isLiquidationPending_) {
        // adjust balances
        (bool isPriceRecent, int256 tempLongBalance, int256 tempVaultBalance) =
            _applyPnlAndFunding(neutralPrice.toUint128(), timestamp.toUint128());

        // liquidate if the price was updated or was already the most recent
        if (isPriceRecent) {
            LiquidationsEffects memory liquidationEffects =
                _liquidatePositions(_lastPrice, iterations, tempLongBalance, tempVaultBalance);

            isLiquidationPending_ = liquidationEffects.isLiquidationPending;
            _balanceLong = liquidationEffects.newLongBalance;
            _balanceVault = liquidationEffects.newVaultBalance;

            bool rebased = _usdnRebase(uint128(neutralPrice), ignoreInterval); // safecast not needed since already done
                // earlier

            if (liquidationEffects.liquidatedTicks > 0) {
                _sendRewardsToLiquidator(
                    liquidationEffects.liquidatedTicks, liquidationEffects.remainingCollateral, rebased, priceData
                );
            }

            liquidatedPositions_ = liquidationEffects.liquidatedPositions;
        }
    }

    /**
     * @notice Refunds any excess ether to the user to prevent locking ETH in the contract.
     * @param securityDepositValue The security deposit value of the action (zero for a validation action).
     * @param amountToRefund The amount to refund to the user:
     *      - the security deposit if executing an action for another user,
     *      - the initialization security deposit in case of a validation action.
     * @param balanceBefore The balance of the contract before the action.
     */
    function _refundExcessEther(uint256 securityDepositValue, uint256 amountToRefund, uint256 balanceBefore) internal {
        uint256 positive = amountToRefund + address(this).balance + msg.value;
        uint256 negative = balanceBefore + securityDepositValue;

        if (negative > positive) {
            revert UsdnProtocolUnexpectedBalance();
        }

        uint256 amount;
        unchecked {
            // we know that positive >= negative, so this subtraction is safe
            amount = positive - negative;
        }

        if (amount != 0) {
            // slither-disable-next-line arbitrary-send-eth
            (bool success,) = payable(msg.sender).call{ value: amount }("");
            if (!success) {
                revert UsdnProtocolEtherRefundFailed();
            }
        }
    }

    function _checkPendingFee() internal {
        // if the pending protocol fee is above the threshold, send it to the fee collector
        if (_pendingProtocolFee >= _feeThreshold) {
            _asset.safeTransfer(_feeCollector, _pendingProtocolFee);
            emit ProtocolFeeDistributed(_feeCollector, _pendingProtocolFee);
            _pendingProtocolFee = 0;
        }
    }
}

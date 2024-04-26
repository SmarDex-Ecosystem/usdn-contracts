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
    PendingActionCommonData,
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
     */
    struct WithdrawalData {
        uint128 pendingActionPrice;
        uint256 totalExpo;
        uint256 balanceLong;
        uint256 balanceVault;
        IUsdn usdn;
    }

    /**
     * @dev Structure to hold the transient data during `_initiateOpenPosition`
     * @param adjustedPrice The adjusted price with position fees applied
     * @param posId The new position id
     * @param liquidationPenalty The liquidation penalty
     * @param leverage The leverage
     * @param positionTotalExpo The total expo of the position
     */
    struct OpenPositionData {
        uint128 adjustedPrice;
        PositionId posId;
        uint8 liquidationPenalty;
        uint128 leverage;
        uint128 positionTotalExpo;
    }

    /**
     * @dev Structure to hold the transient data during `_initiateClosePosition`
     * @param pos The position to close
     * @param liquidationPenalty The liquidation penalty
     * @param securityDepositValue The security deposit value
     * @param totalExpoToClose The total expo to close
     * @param lastPrice The price after the last balances update
     * @param tempTransfer The value of the position that was removed from the long balance
     * @param longTradingExpo The long trading expo
     * @param liqMulAcc The liquidation multiplier accumulator
     */
    struct ClosePositionData {
        Position pos;
        uint8 liquidationPenalty;
        uint64 securityDepositValue;
        uint128 totalExpoToClose;
        uint128 lastPrice;
        uint256 tempTransfer;
        uint256 longTradingExpo;
        HugeUint.Uint512 liqMulAcc;
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
        uint256 securityDepositValue = _securityDepositValue;
        if (msg.value < securityDepositValue) {
            revert UsdnProtocolSecurityDepositTooLow();
        }
        uint256 balanceBefore = address(this).balance;

        uint256 amountToRefund = _initiateDeposit(msg.sender, to, amount, currentPriceData);
        unchecked {
            amountToRefund += _executePendingActionOrRevert(previousActionsData);
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

        uint256 amountToRefund = _validateDeposit(msg.sender, depositPriceData);
        unchecked {
            amountToRefund += _executePendingActionOrRevert(previousActionsData);
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
        uint256 securityDepositValue = _securityDepositValue;
        if (msg.value < securityDepositValue) {
            revert UsdnProtocolSecurityDepositTooLow();
        }

        uint256 balanceBefore = address(this).balance;

        uint256 amountToRefund = _initiateWithdrawal(msg.sender, to, usdnShares, currentPriceData);
        unchecked {
            amountToRefund += _executePendingActionOrRevert(previousActionsData);
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

        uint256 amountToRefund = _validateWithdrawal(msg.sender, withdrawalPriceData);
        unchecked {
            amountToRefund += _executePendingActionOrRevert(previousActionsData);
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
    ) external payable initializedAndNonReentrant returns (int24 tick_, uint256 tickVersion_, uint256 index_) {
        uint256 securityDepositValue = _securityDepositValue;
        if (msg.value < securityDepositValue) {
            revert UsdnProtocolSecurityDepositTooLow();
        }

        uint256 balanceBefore = address(this).balance;
        uint256 amountToRefund;

        PositionId memory posId;
        (posId, amountToRefund) = _initiateOpenPosition(msg.sender, to, amount, desiredLiqPrice, currentPriceData);
        tick_ = posId.tick;
        tickVersion_ = posId.tickVersion;
        index_ = posId.index;

        unchecked {
            amountToRefund += _executePendingActionOrRevert(previousActionsData);
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

        uint256 amountToRefund = _validateOpenPosition(msg.sender, openPriceData);
        unchecked {
            amountToRefund += _executePendingActionOrRevert(previousActionsData);
        }
        _refundExcessEther(0, amountToRefund, balanceBefore);
        _checkPendingFee();
    }

    /// @inheritdoc IUsdnProtocolActions
    function initiateClosePosition(
        int24 tick,
        uint256 tickVersion,
        uint256 index,
        uint128 amountToClose,
        bytes calldata currentPriceData,
        PreviousActionsData calldata previousActionsData,
        address to
    ) external payable initializedAndNonReentrant {
        uint256 securityDepositValue = _securityDepositValue;
        if (msg.value < securityDepositValue) {
            revert UsdnProtocolSecurityDepositTooLow();
        }

        uint256 balanceBefore = address(this).balance;

        uint256 amountToRefund = _initiateClosePosition(
            msg.sender,
            to,
            PositionId({ tick: tick, tickVersion: tickVersion, index: index }),
            amountToClose,
            currentPriceData
        );
        unchecked {
            amountToRefund += _executePendingActionOrRevert(previousActionsData);
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

        uint256 amountToRefund = _validateClosePosition(msg.sender, closePriceData);
        unchecked {
            amountToRefund += _executePendingActionOrRevert(previousActionsData);
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

        liquidatedPositions_ =
            _applyPnlAndFundingAndLiquidate(currentPrice.neutralPrice, currentPrice.timestamp, iterations, true);

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
     */
    function _sendRewardsToLiquidator(uint16 liquidatedTicks, int256 remainingCollateral, bool rebased) internal {
        // Get how much we should give to the liquidator as rewards
        uint256 liquidationRewards =
            _liquidationRewardsManager.getLiquidationRewards(liquidatedTicks, remainingCollateral, rebased);

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
     * @param currentPriceData The current price data
     * @return securityDepositValue_ The security deposit value
     */
    function _initiateDeposit(address user, address to, uint128 amount, bytes calldata currentPriceData)
        internal
        returns (uint256 securityDepositValue_)
    {
        if (to == address(0)) {
            revert UsdnProtocolInvalidAddressTo();
        }
        if (amount == 0) {
            revert UsdnProtocolZeroAmount();
        }

        PriceInfo memory currentPrice =
            _getOraclePrice(ProtocolAction.InitiateDeposit, block.timestamp, currentPriceData);

        _applyPnlAndFundingAndLiquidate(currentPrice.neutralPrice, currentPrice.timestamp, _liquidationIteration, false);

        _checkImbalanceLimitDeposit(amount);

        // Apply fees on price
        uint128 pendingActionPrice =
            (currentPrice.price - currentPrice.price * _positionFeeBps / BPS_DIVISOR).toUint128();

        DepositPendingAction memory pendingAction = DepositPendingAction({
            common: PendingActionCommonData({
                action: ProtocolAction.ValidateDeposit,
                timestamp: uint40(block.timestamp),
                user: user,
                to: to,
                securityDepositValue: _securityDepositValue
            }),
            _unused: 0,
            amount: amount,
            assetPrice: pendingActionPrice,
            totalExpo: _totalExpo,
            balanceVault: _vaultAssetAvailable(_totalExpo, _balanceVault, _balanceLong, pendingActionPrice, _lastPrice)
                .toUint256(),
            balanceLong: _balanceLong,
            usdnTotalSupply: _usdn.totalSupply()
        });

        securityDepositValue_ = _addPendingAction(user, _convertDepositPendingAction(pendingAction));

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
        returns (uint256 securityDepositValue_)
    {
        PendingAction memory pending = _getAndClearPendingAction(user);

        // check type of action
        if (pending.common.action != ProtocolAction.ValidateDeposit) {
            revert UsdnProtocolInvalidPendingAction();
        }
        // sanity check
        if (pending.common.user != user) {
            revert UsdnProtocolInvalidPendingAction();
        }

        _validateDepositWithAction(pending, priceData);
        return pending.common.securityDepositValue;
    }

    function _validateDepositWithAction(PendingAction memory pending, bytes calldata priceData) internal {
        DepositPendingAction memory deposit = _toDepositPendingAction(pending);

        PriceInfo memory currentPrice =
            _getOraclePrice(ProtocolAction.ValidateDeposit, deposit.common.timestamp, priceData);

        // adjust balances
        _applyPnlAndFundingAndLiquidate(currentPrice.neutralPrice, currentPrice.timestamp, _liquidationIteration, false);

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

        _usdn.mint(deposit.common.to, usdnToMint);
        emit ValidatedDeposit(
            deposit.common.user, deposit.common.to, deposit.amount, usdnToMint, deposit.common.timestamp
        );
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

        _applyPnlAndFundingAndLiquidate(currentPrice.neutralPrice, currentPrice.timestamp, _liquidationIteration, false);

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
     * @notice Prepare the pending action struct for a withdrawal and add it to the queue.
     * @param data The withdrawal action data
     * @return securityDepositValue_ The security deposit value
     */
    function _createWithdrawalPendingAction(address user, address to, uint152 usdnShares, WithdrawalData memory data)
        internal
        returns (uint256 securityDepositValue_)
    {
        PendingAction memory action = _convertWithdrawalPendingAction(
            WithdrawalPendingAction({
                common: PendingActionCommonData({
                    action: ProtocolAction.ValidateWithdrawal,
                    timestamp: uint40(block.timestamp),
                    user: user,
                    to: to,
                    securityDepositValue: _securityDepositValue
                }),
                sharesLSB: _calcWithdrawalAmountLSB(usdnShares),
                sharesMSB: _calcWithdrawalAmountMSB(usdnShares),
                assetPrice: data.pendingActionPrice,
                totalExpo: data.totalExpo,
                balanceVault: data.balanceVault,
                balanceLong: data.balanceLong,
                usdnTotalShares: data.usdn.totalShares()
            })
        );
        securityDepositValue_ = _addPendingAction(user, action);
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
     * @param currentPriceData The current price data
     * @return securityDepositValue_ The security deposit value
     */
    function _initiateWithdrawal(address user, address to, uint152 usdnShares, bytes calldata currentPriceData)
        internal
        returns (uint256 securityDepositValue_)
    {
        if (to == address(0)) {
            revert UsdnProtocolInvalidAddressTo();
        }
        if (usdnShares == 0) {
            revert UsdnProtocolZeroAmount();
        }

        WithdrawalData memory data = _prepareWithdrawalData(usdnShares, currentPriceData);

        securityDepositValue_ = _createWithdrawalPendingAction(user, to, usdnShares, data);

        // retrieve the USDN tokens, checks that balance is sufficient
        data.usdn.transferSharesFrom(user, address(this), usdnShares);

        emit InitiatedWithdrawal(user, to, data.usdn.convertToTokens(usdnShares), block.timestamp);
    }

    function _validateWithdrawal(address user, bytes calldata priceData)
        internal
        returns (uint256 securityDepositValue_)
    {
        PendingAction memory pending = _getAndClearPendingAction(user);

        // check type of action
        if (pending.common.action != ProtocolAction.ValidateWithdrawal) {
            revert UsdnProtocolInvalidPendingAction();
        }
        // sanity check
        if (pending.common.user != user) {
            revert UsdnProtocolInvalidPendingAction();
        }

        _validateWithdrawalWithAction(pending, priceData);
        return pending.common.securityDepositValue;
    }

    function _validateWithdrawalWithAction(PendingAction memory pending, bytes calldata priceData) internal {
        WithdrawalPendingAction memory withdrawal = _toWithdrawalPendingAction(pending);

        PriceInfo memory currentPrice =
            _getOraclePrice(ProtocolAction.ValidateWithdrawal, withdrawal.common.timestamp, priceData);

        _applyPnlAndFundingAndLiquidate(currentPrice.neutralPrice, currentPrice.timestamp, _liquidationIteration, false);

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

        // assetToTransfer = amountUsdn * usdnPrice / assetPrice = amountUsdn * assetAvailable / totalSupply
        //                 = shares * assetAvailable / usdnTotalShares
        uint256 assetToTransfer = FixedPointMathLib.fullMulDiv(shares, available, withdrawal.usdnTotalShares);

        // we have the USDN in the contract already
        IUsdn usdn = _usdn;
        usdn.burnShares(shares);

        // send the asset to the user
        if (assetToTransfer > 0) {
            _balanceVault -= assetToTransfer;
            _asset.safeTransfer(withdrawal.common.to, assetToTransfer);
        }

        emit ValidatedWithdrawal(
            withdrawal.common.user,
            withdrawal.common.to,
            assetToTransfer,
            usdn.convertToTokens(shares),
            withdrawal.common.timestamp
        );
    }

    /**
     * @notice Update protocol balances, then prepare the data for the initiate open position action.
     * @dev Reverts if the imbalance limit is reached, or if the safety margin is not respected.
     * @param amount The amount of wstETH to deposit.
     * @param desiredLiqPrice The desired liquidation price, including the liquidation penalty.
     * @param currentPriceData The current price data
     */
    function _prepareOpenPositionData(uint128 amount, uint128 desiredLiqPrice, bytes calldata currentPriceData)
        internal
        returns (OpenPositionData memory data_)
    {
        PriceInfo memory currentPrice =
            _getOraclePrice(ProtocolAction.InitiateOpenPosition, block.timestamp, currentPriceData);
        data_.adjustedPrice = (currentPrice.price + (currentPrice.price * _positionFeeBps) / BPS_DIVISOR).toUint128();

        if (FixedPointMathLib.fullMulDiv(amount, data_.adjustedPrice, 10 ** _assetDecimals) < _minLongPosition) {
            revert UsdnProtocolLongPositionTooSmall();
        }

        uint128 neutralPrice = currentPrice.neutralPrice.toUint128();

        _applyPnlAndFundingAndLiquidate(neutralPrice, currentPrice.timestamp, _liquidationIteration, false);

        // we calculate the closest valid tick down for the desired liq price with liquidation penalty
        data_.posId.tick = getEffectiveTickForPrice(desiredLiqPrice);
        data_.liquidationPenalty = getTickLiquidationPenalty(data_.posId.tick);

        // Calculate effective liquidation price
        uint128 liqPrice = getEffectivePriceForTick(data_.posId.tick);

        // Liquidation price must be at least x% below current price
        _checkSafetyMargin(neutralPrice, liqPrice);

        (data_.leverage, data_.positionTotalExpo) =
            _getOpenPositionLeverage(data_.posId.tick, data_.liquidationPenalty, data_.adjustedPrice, amount);
        _checkImbalanceLimitOpen(data_.positionTotalExpo, amount);
    }

    /**
     * @notice Prepare the pending action struct for an open position and add it to the queue.
     * @param user The address of the user initiating the open position.
     * @param to The address that will be the owner of the position
     * @param data The open position action data
     * @return securityDepositValue_ The security deposit value
     */
    function _createOpenPendingAction(address user, address to, OpenPositionData memory data)
        internal
        returns (uint256 securityDepositValue_)
    {
        LongPendingAction memory action = LongPendingAction({
            common: PendingActionCommonData({
                action: ProtocolAction.ValidateOpenPosition,
                timestamp: uint40(block.timestamp),
                user: user,
                to: to,
                securityDepositValue: _securityDepositValue
            }),
            tick: data.posId.tick,
            closeAmount: 0,
            closePosTotalExpo: 0,
            tickVersion: data.posId.tickVersion,
            index: data.posId.index,
            closeLiqMultiplier: 0,
            closeTempTransfer: 0
        });
        securityDepositValue_ = _addPendingAction(user, _convertLongPendingAction(action));
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
     * @param currentPriceData  The current price data (used to calculate the temporary leverage and entry price,
     * pending validation)
     * @return posId_ The unique index of the opened position
     * @return securityDepositValue_ The security deposit value
     */
    function _initiateOpenPosition(
        address user,
        address to,
        uint128 amount,
        uint128 desiredLiqPrice,
        bytes calldata currentPriceData
    ) internal returns (PositionId memory posId_, uint256 securityDepositValue_) {
        if (to == address(0)) {
            revert UsdnProtocolInvalidAddressTo();
        }
        if (amount == 0) {
            revert UsdnProtocolZeroAmount();
        }

        OpenPositionData memory data = _prepareOpenPositionData(amount, desiredLiqPrice, currentPriceData);

        // Register position and adjust contract state
        Position memory long = Position({
            user: to,
            amount: amount,
            totalExpo: data.positionTotalExpo,
            timestamp: uint40(block.timestamp)
        });
        (data.posId.tickVersion, data.posId.index) = _saveNewPosition(data.posId.tick, long, data.liquidationPenalty);
        posId_ = data.posId;

        securityDepositValue_ = _createOpenPendingAction(user, to, data);

        _asset.safeTransferFrom(user, address(this), amount);

        emit InitiatedOpenPosition(
            user,
            to,
            uint40(block.timestamp),
            data.leverage,
            amount,
            data.adjustedPrice,
            posId_.tick,
            posId_.tickVersion,
            posId_.index
        );
    }

    function _validateOpenPosition(address user, bytes calldata priceData)
        internal
        returns (uint256 securityDepositValue_)
    {
        PendingAction memory pending = _getAndClearPendingAction(user);

        // check type of action
        if (pending.common.action != ProtocolAction.ValidateOpenPosition) {
            revert UsdnProtocolInvalidPendingAction();
        }
        // sanity check
        if (pending.common.user != user) {
            revert UsdnProtocolInvalidPendingAction();
        }

        _validateOpenPositionWithAction(pending, priceData);
        return pending.common.securityDepositValue;
    }

    function _validateOpenPositionWithAction(PendingAction memory pending, bytes calldata priceData) internal {
        LongPendingAction memory long = _toLongPendingAction(pending);

        uint128 startPrice;
        {
            PriceInfo memory currentPrice =
                _getOraclePrice(ProtocolAction.ValidateOpenPosition, long.common.timestamp, priceData);

            // Apply fees on price
            startPrice = (currentPrice.price + (currentPrice.price * _positionFeeBps) / BPS_DIVISOR).toUint128();

            _applyPnlAndFundingAndLiquidate(
                currentPrice.neutralPrice, currentPrice.timestamp, _liquidationIteration, false
            );
        }

        (bytes32 tickHash, uint256 version) = _tickHash(long.tick);
        if (version != long.tickVersion) {
            // The current tick version doesn't match the version from the pending action.
            // This means the position has been liquidated in the mean time
            emit StalePendingActionRemoved(long.common.user, long.tick, long.tickVersion, long.index);
            return;
        }

        // Get the position
        Position memory pos = _longPositions[tickHash][long.index];

        // Re-calculate leverage
        uint128 liqPriceWithoutPenalty =
            getEffectivePriceForTick(long.tick - int24(uint24(_liquidationPenalty)) * _tickSpacing);
        // reverts if liquidationPrice >= entryPrice
        uint128 leverage = _getLeverage(startPrice, liqPriceWithoutPenalty);
        // Leverage is always greater than 1 (liquidationPrice is positive).
        // Even if it drops below _minLeverage between the initiate and validate actions, we still allow it.
        // However, if the leverage exceeds max leverage, then we adjust the liquidation price (tick) to have a leverage
        // of _maxLeverage
        if (leverage > _maxLeverage) {
            // theoretical liquidation price for _maxLeverage
            liqPriceWithoutPenalty = _getLiquidationPrice(startPrice, _maxLeverage.toUint128());
            // adjust to closest valid tick down
            int24 tickWithoutPenalty = getEffectiveTickForPrice(liqPriceWithoutPenalty);

            // apply liquidation penalty with the current penalty setting
            uint8 currentLiqPenalty = _liquidationPenalty;
            int24 tick = tickWithoutPenalty + int24(uint24(currentLiqPenalty)) * _tickSpacing;
            // retrieve the actual penalty for this tick we want to use
            uint8 liquidationPenalty = getTickLiquidationPenalty(tick);
            // check if the penalty for that tick is different from the current setting
            if (liquidationPenalty == currentLiqPenalty) {
                // Since the tick's penalty is the same as what we assumed, we can use the `tickWithoutPenalty` from
                // above.
                // Retrieve exact liquidation price without penalty
                liqPriceWithoutPenalty = getEffectivePriceForTick(tickWithoutPenalty);
            } else {
                // The tick's imposed penalty is different from the current setting, so the `tickWithoutPenalty` we
                // calculated above can't be used to calculate the leverage.
                // We must instead use the tick's penalty to find the new `liqPriceWithoutPenalty` and calculate the
                // leverage.

                // Note: In case the tick liquidation penalty is lower than the current setting, it might lead to a
                // leverage that exceeds the max leverage slightly. We allow this behavior in this rare occurrence.

                // Retrieve exact liquidation price without penalty.
                liqPriceWithoutPenalty =
                    getEffectivePriceForTick(tick - int24(uint24(liquidationPenalty)) * _tickSpacing);
            }
            // recalculate the leverage with the new liquidation price
            leverage = _getLeverage(startPrice, liqPriceWithoutPenalty);

            // remove the position from the old tick
            _removeAmountFromPosition(long.tick, long.index, pos, pos.amount, pos.totalExpo);

            // update position total expo
            pos.totalExpo = _calculatePositionTotalExpo(pos.amount, startPrice, liqPriceWithoutPenalty);

            // insert position into new tick, update tickVersion and index
            (uint256 tickVersion, uint256 index) = _saveNewPosition(tick, pos, liquidationPenalty);

            // emit LiquidationPriceUpdated
            emit LiquidationPriceUpdated(long.tick, long.tickVersion, long.index, tick, tickVersion, index);
            emit ValidatedOpenPosition(long.common.user, long.common.to, leverage, startPrice, tick, tickVersion, index);
        } else {
            // Calculate the new total expo
            uint128 expoBefore = pos.totalExpo;
            uint128 expoAfter = _calculatePositionTotalExpo(pos.amount, startPrice, liqPriceWithoutPenalty);

            // Update the total expo of the position
            _longPositions[tickHash][long.index].totalExpo = expoAfter;
            // Update the total expo by adding the position's new expo and removing the old one.
            // Do not use += or it will underflow
            _totalExpo = _totalExpo + expoAfter - expoBefore;

            // update the tick data and the liqMultiplierAccumulator
            {
                TickData storage tickData = _tickData[tickHash];
                uint256 unadjustedTickPrice =
                    TickMath.getPriceAtTick(long.tick - int24(uint24(tickData.liquidationPenalty)) * _tickSpacing);
                tickData.totalExpo = tickData.totalExpo + expoAfter - expoBefore;
                _liqMultiplierAccumulator = _liqMultiplierAccumulator.add(
                    HugeUint.wrap(expoAfter * unadjustedTickPrice)
                ).sub(HugeUint.wrap(expoBefore * unadjustedTickPrice));
            }

            emit ValidatedOpenPosition(
                long.common.user, long.common.to, leverage, startPrice, long.tick, long.tickVersion, long.index
            );
        }
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
        pure
    {
        if (pos.user != user) {
            revert UsdnProtocolUnauthorized();
        }

        if (amountToClose > pos.amount) {
            revert UsdnProtocolAmountToCloseHigherThanPositionAmount(amountToClose, pos.amount);
        }

        if (amountToClose == 0) {
            revert UsdnProtocolAmountToCloseIsZero();
        }

        if (to == address(0)) {
            revert UsdnProtocolInvalidAddressTo();
        }
    }

    /**
     * @notice Update protocol balances, then prepare the data for the initiate close position action.
     * @dev Reverts if the imbalance limit is reached, or if any of the checks in `_checkInitiateClosePosition` fail.
     * Returns without creating a pending action if the position gets liquidated in this transaction.
     * @param user The address of the user initiating the close position.
     * @param to The address that will receive the assets
     * @param posId The unique identifier of the position
     * @param amountToClose The amount of collateral to remove from the position's amount
     * @param currentPriceData The current price data
     * @return data_ The close position data
     */
    function _prepareClosePositionData(
        address user,
        address to,
        PositionId memory posId,
        uint128 amountToClose,
        bytes calldata currentPriceData
    ) internal returns (ClosePositionData memory data_, bool liq_) {
        (data_.pos, data_.liquidationPenalty) = getLongPosition(posId.tick, posId.tickVersion, posId.index);

        _checkInitiateClosePosition(user, to, amountToClose, data_.pos);

        PriceInfo memory currentPrice =
            _getOraclePrice(ProtocolAction.InitiateClosePosition, block.timestamp, currentPriceData);

        _applyPnlAndFundingAndLiquidate(currentPrice.neutralPrice, currentPrice.timestamp, _liquidationIteration, false);

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
        (data_.tempTransfer,) = _assetToTransfer(
            data_.lastPrice,
            getEffectivePriceForTick(
                posId.tick - int24(uint24(data_.liquidationPenalty)) * _tickSpacing,
                data_.lastPrice,
                data_.longTradingExpo,
                data_.liqMulAcc
            ),
            data_.totalExpoToClose,
            0
        );

        data_.securityDepositValue = _securityDepositValue;
    }

    /**
     * @notice Prepare the pending action struct for the close position action and add it to the queue.
     * @param user The address of the user initiating the close position.
     * @param to The address that will receive the assets
     * @param posId The unique identifier of the position
     * @param amountToClose The amount of collateral to remove from the position's amount
     * @param data The close position data
     * @return securityDepositValue_ The security deposit value
     */
    function _createClosePendingAction(
        address user,
        address to,
        PositionId memory posId,
        uint128 amountToClose,
        ClosePositionData memory data
    ) internal returns (uint256 securityDepositValue_) {
        LongPendingAction memory action = LongPendingAction({
            common: PendingActionCommonData({
                action: ProtocolAction.ValidateClosePosition,
                timestamp: uint40(block.timestamp),
                user: user,
                to: to,
                securityDepositValue: data.securityDepositValue
            }),
            tick: posId.tick,
            closeAmount: amountToClose,
            closePosTotalExpo: data.totalExpoToClose,
            tickVersion: posId.tickVersion,
            index: posId.index,
            closeLiqMultiplier: _calcFixedPrecisionMultiplier(data.lastPrice, data.longTradingExpo, data.liqMulAcc),
            closeTempTransfer: data.tempTransfer
        });
        securityDepositValue_ = _addPendingAction(user, _convertLongPendingAction(action));
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
     * @param currentPriceData The current price data
     * @return securityDepositValue_ The security deposit value
     */
    function _initiateClosePosition(
        address user,
        address to,
        PositionId memory posId,
        uint128 amountToClose,
        bytes calldata currentPriceData
    ) internal returns (uint256 securityDepositValue_) {
        (ClosePositionData memory data, bool liq) =
            _prepareClosePositionData(user, to, posId, amountToClose, currentPriceData);
        if (liq) {
            // position was liquidated in this transaction
            return 0;
        }

        securityDepositValue_ = _createClosePendingAction(user, to, posId, amountToClose, data);

        _balanceLong -= data.tempTransfer;

        _removeAmountFromPosition(posId.tick, posId.index, data.pos, amountToClose, data.totalExpoToClose);

        emit InitiatedClosePosition(
            user,
            to,
            posId.tick,
            posId.tickVersion,
            posId.index,
            data.pos.amount,
            amountToClose,
            data.pos.totalExpo - data.totalExpoToClose
        );
    }

    function _validateClosePosition(address user, bytes calldata priceData)
        internal
        returns (uint256 securityDepositValue_)
    {
        PendingAction memory pending = _getAndClearPendingAction(user);

        // check type of action
        if (pending.common.action != ProtocolAction.ValidateClosePosition) {
            revert UsdnProtocolInvalidPendingAction();
        }
        // sanity check
        if (pending.common.user != user) {
            revert UsdnProtocolInvalidPendingAction();
        }

        _validateClosePositionWithAction(pending, priceData);
        return pending.common.securityDepositValue;
    }

    function _validateClosePositionWithAction(PendingAction memory pending, bytes calldata priceData) internal {
        LongPendingAction memory long = _toLongPendingAction(pending);

        PriceInfo memory currentPrice =
            _getOraclePrice(ProtocolAction.ValidateClosePosition, long.common.timestamp, priceData);

        _applyPnlAndFundingAndLiquidate(currentPrice.neutralPrice, currentPrice.timestamp, _liquidationIteration, false);

        // Apply fees on price
        uint128 priceWithFees = (currentPrice.price - (currentPrice.price * _positionFeeBps) / BPS_DIVISOR).toUint128();

        (uint256 assetToTransfer,) = _assetToTransfer(
            priceWithFees,
            _getEffectivePriceForTick(
                long.tick - int24(uint24(getTickLiquidationPenalty(long.tick))) * _tickSpacing, long.closeLiqMultiplier
            ),
            long.closePosTotalExpo,
            long.closeTempTransfer
        );

        // get liquidation price (with liq penalty) to check if position was valid at `timestamp + validationDelay`
        uint128 liquidationPrice = _getEffectivePriceForTick(long.tick, long.closeLiqMultiplier);

        if (currentPrice.neutralPrice <= liquidationPrice) {
            // Position should be liquidated, we don't transfer assets to the user.
            // Position was already removed from tick so no additional bookkeeping is necessary.
            // Credit the full amount to the vault to preserve the total balance invariant.
            _balanceVault += long.closeTempTransfer;
            emit LiquidatedPosition(
                long.common.user, long.tick, long.tickVersion, long.index, currentPrice.neutralPrice, liquidationPrice
            );
            return;
        }

        // Normally, the position value should be smaller than `long.closeTempTransfer` (due to the position fee).
        // We can send the difference (any remaining collateral) to the vault.
        // If the price increased since the initiate, it's possible that the position value is higher than the
        // `long.closeTempTransfer`. In this case, we need to take the missing assets from the vault.
        if (assetToTransfer < long.closeTempTransfer) {
            uint256 remainingCollateral;
            unchecked {
                remainingCollateral = long.closeTempTransfer - assetToTransfer;
            }
            _balanceVault += remainingCollateral;
        } else if (assetToTransfer > long.closeTempTransfer) {
            uint256 missingValue;
            unchecked {
                missingValue = assetToTransfer - long.closeTempTransfer;
            }
            _balanceVault -= missingValue;
        }

        // send the asset to the user
        if (assetToTransfer > 0) {
            _asset.safeTransfer(long.common.to, assetToTransfer);
        }

        emit ValidatedClosePosition(
            long.common.user,
            long.common.to,
            long.tick,
            long.tickVersion,
            long.index,
            assetToTransfer,
            assetToTransfer.toInt256() - _toInt256(long.closeAmount)
        );
    }

    /**
     * @notice During creation of a new long position, calculate the leverage and total exposure of the position.
     * @param tick The tick of the position.
     * @param liquidationPenalty The liquidation penalty of the tick.
     * @param adjustedPrice The adjusted price of the asset.
     * @param amount The amount of collateral.
     * @return leverage_ The leverage of the position.
     * @return totalExpo_ The total exposure of the position.
     */
    function _getOpenPositionLeverage(int24 tick, uint8 liquidationPenalty, uint128 adjustedPrice, uint128 amount)
        internal
        view
        returns (uint128 leverage_, uint128 totalExpo_)
    {
        // remove liquidation penalty for leverage calculation
        uint128 liqPriceWithoutPenalty =
            getEffectivePriceForTick(tick - int24(uint24(liquidationPenalty)) * _tickSpacing);
        totalExpo_ = _calculatePositionTotalExpo(amount, adjustedPrice, liqPriceWithoutPenalty);

        // calculate position leverage
        // reverts if liquidationPrice >= entryPrice
        leverage_ = _getLeverage(adjustedPrice, liqPriceWithoutPenalty);
        if (leverage_ < _minLeverage) {
            revert UsdnProtocolLeverageTooLow();
        }
        if (leverage_ > _maxLeverage) {
            revert UsdnProtocolLeverageTooHigh();
        }
    }

    /**
     * @notice Calculate how much wstETH must be transferred to a user to close a position.
     * @dev The amount is bound by the amount of wstETH available in the long side.
     * @param priceWithFees The current price of the asset, adjusted with fees
     * @param liqPriceWithoutPenalty The liquidation price without penalty
     * @param posExpo The total expo of the position
     * @param tempTransferred An amount that was already subtracted from the long balance
     * @return assetToTransfer_ The amount of assets to transfer to the user, bound by zero and the available balance
     * @return positionValue_ The position value, which can be negative in case of bad debt
     */
    function _assetToTransfer(
        uint128 priceWithFees,
        uint128 liqPriceWithoutPenalty,
        uint128 posExpo,
        uint256 tempTransferred
    ) internal view returns (uint256 assetToTransfer_, int256 positionValue_) {
        // The available amount of asset on the long side (with the current balance)
        uint256 available = _balanceLong + tempTransferred;

        // Calculate position value
        positionValue_ = _positionValue(priceWithFees, liqPriceWithoutPenalty, posExpo);
        // TODO: maybe we don't need to return this value anymore

        if (positionValue_ <= 0) {
            assetToTransfer_ = 0;
        } else if (positionValue_ > available.toInt256()) {
            assetToTransfer_ = available;
        } else {
            assetToTransfer_ = uint256(positionValue_);
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
        if (pending.common.action == ProtocolAction.None) {
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
        _clearPendingAction(pending.common.user);
        if (pending.common.action == ProtocolAction.ValidateDeposit) {
            _validateDepositWithAction(pending, priceData);
        } else if (pending.common.action == ProtocolAction.ValidateWithdrawal) {
            _validateWithdrawalWithAction(pending, priceData);
        } else if (pending.common.action == ProtocolAction.ValidateOpenPosition) {
            _validateOpenPositionWithAction(pending, priceData);
        } else if (pending.common.action == ProtocolAction.ValidateClosePosition) {
            _validateClosePositionWithAction(pending, priceData);
        }
        success_ = true;
        executed_ = true;
        securityDepositValue_ = pending.common.securityDepositValue;
        emit SecurityDepositRefunded(pending.common.user, msg.sender, securityDepositValue_);
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
     * @return liquidatedPositions_ The number of positions that were liquidated.
     * @dev If there were any liquidated positions, it sends rewards to the msg.sender.
     */
    function _applyPnlAndFundingAndLiquidate(
        uint256 neutralPrice,
        uint256 timestamp,
        uint16 iterations,
        bool ignoreInterval
    ) internal returns (uint256 liquidatedPositions_) {
        // adjust balances
        (bool priceUpdated, int256 tempLongBalance, int256 tempVaultBalance) =
            _applyPnlAndFunding(neutralPrice.toUint128(), timestamp.toUint128());

        // liquidate if price is more recent than _lastPrice
        if (priceUpdated) {
            LiquidationsEffects memory liquidationEffects =
                _liquidatePositions(neutralPrice, iterations, tempLongBalance, tempVaultBalance);

            _balanceLong = liquidationEffects.newLongBalance;
            _balanceVault = liquidationEffects.newVaultBalance;

            bool rebased = _usdnRebase(uint128(neutralPrice), ignoreInterval); // safecast not needed since already done
                // earlier

            if (liquidationEffects.liquidatedTicks > 0) {
                _sendRewardsToLiquidator(
                    liquidationEffects.liquidatedTicks, liquidationEffects.remainingCollateral, rebased
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

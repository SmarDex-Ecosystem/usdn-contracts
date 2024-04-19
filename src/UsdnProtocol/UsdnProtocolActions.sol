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
    PositionId
} from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import { UsdnProtocolLong } from "src/UsdnProtocol/UsdnProtocolLong.sol";
import { PriceInfo } from "src/interfaces/OracleMiddleware/IOracleMiddlewareTypes.sol";
import { IUsdn } from "src/interfaces/Usdn/IUsdn.sol";
import { SignedMath } from "src/libraries/SignedMath.sol";

abstract contract UsdnProtocolActions is IUsdnProtocolActions, UsdnProtocolLong {
    using SafeERC20 for IERC20Metadata;
    using SafeERC20 for IUsdn;
    using SafeCast for uint256;
    using SafeCast for int256;
    using LibBitmap for LibBitmap.Bitmap;
    using SignedMath for int256;

    /// @inheritdoc IUsdnProtocolActions
    uint256 public constant MIN_USDN_SUPPLY = 1000;

    /// @inheritdoc IUsdnProtocolActions
    function initiateDeposit(
        uint128 amount,
        bytes calldata currentPriceData,
        PreviousActionsData calldata previousActionsData
    ) external payable initializedAndNonReentrant {
        uint256 securityDepositValue = _securityDepositValue;
        if (msg.value < securityDepositValue) {
            revert UsdnProtocolSecurityDepositTooLow();
        }

        uint256 balanceBefore = address(this).balance;

        uint256 amountToRefund = _initiateDeposit(msg.sender, amount, currentPriceData);
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
        PreviousActionsData calldata previousActionsData
    ) external payable initializedAndNonReentrant {
        uint256 securityDepositValue = _securityDepositValue;
        if (msg.value < securityDepositValue) {
            revert UsdnProtocolSecurityDepositTooLow();
        }

        uint256 balanceBefore = address(this).balance;

        uint256 amountToRefund = _initiateWithdrawal(msg.sender, usdnShares, currentPriceData);
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
        PreviousActionsData calldata previousActionsData
    ) external payable initializedAndNonReentrant returns (int24 tick_, uint256 tickVersion_, uint256 index_) {
        uint256 securityDepositValue = _securityDepositValue;
        if (msg.value < securityDepositValue) {
            revert UsdnProtocolSecurityDepositTooLow();
        }

        uint256 balanceBefore = address(this).balance;
        uint256 amountToRefund;

        PositionId memory posId;
        (posId, amountToRefund) = _initiateOpenPosition(msg.sender, amount, desiredLiqPrice, currentPriceData);
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
        PreviousActionsData calldata previousActionsData
    ) external payable initializedAndNonReentrant {
        uint256 securityDepositValue = _securityDepositValue;
        if (msg.value < securityDepositValue) {
            revert UsdnProtocolSecurityDepositTooLow();
        }

        uint256 balanceBefore = address(this).balance;

        uint256 amountToRefund = _initiateClosePosition(
            msg.sender,
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
        PriceInfo memory currentPrice = _getOraclePrice(ProtocolAction.Liquidation, block.timestamp, currentPriceData);

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
     * @param closeTotalExpoValue The close position total expo value
     * @param closeCollatValue The close position collateral value
     */
    function _checkImbalanceLimitClose(uint256 closeTotalExpoValue, uint256 closeCollatValue) internal view {
        int256 closeExpoImbalanceLimitBps = _closeExpoImbalanceLimitBps;

        // early return in case limit is disabled
        if (closeExpoImbalanceLimitBps == 0) {
            return;
        }

        int256 newLongExpo = (_totalExpo.toInt256().safeSub(closeTotalExpoValue.toInt256())).safeSub(
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
     * @param amount The amount of wstETH to deposit.
     * @param currentPriceData The current price data
     * @return securityDepositValue_ The security deposit value
     */
    function _initiateDeposit(address user, uint128 amount, bytes calldata currentPriceData)
        internal
        returns (uint256 securityDepositValue_)
    {
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
            action: ProtocolAction.ValidateDeposit,
            timestamp: uint40(block.timestamp),
            user: user,
            securityDepositValue: (_securityDepositValue / SECURITY_DEPOSIT_FACTOR).toUint24(),
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

        emit InitiatedDeposit(user, amount, block.timestamp);
    }

    function _validateDeposit(address user, bytes calldata priceData)
        internal
        returns (uint256 securityDepositValue_)
    {
        PendingAction memory pending = _getAndClearPendingAction(user);

        // check type of action
        if (pending.action != ProtocolAction.ValidateDeposit) {
            revert UsdnProtocolInvalidPendingAction();
        }
        // sanity check
        if (pending.user != user) {
            revert UsdnProtocolInvalidPendingAction();
        }

        _validateDepositWithAction(pending, priceData);
        return (pending.securityDepositValue * SECURITY_DEPOSIT_FACTOR);
    }

    function _validateDepositWithAction(PendingAction memory pending, bytes calldata priceData) internal {
        DepositPendingAction memory deposit = _toDepositPendingAction(pending);

        PriceInfo memory currentPrice = _getOraclePrice(ProtocolAction.ValidateDeposit, deposit.timestamp, priceData);

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

        _usdn.mint(deposit.user, usdnToMint);
        emit ValidatedDeposit(deposit.user, deposit.amount, usdnToMint, deposit.timestamp);
    }

    /**
     * @notice Initiate a withdrawal of assets from the vault by providing USDN tokens.
     * @dev Consult the current oracle middleware implementation to know the expected format for the price data, using
     * the `ProtocolAction.InitiateWithdrawal` action.
     * The price validation might require payment according to the return value of the `getValidationCost` function
     * of the middleware.
     * @param user The address of the user initiating the withdrawal.
     * @param usdnShares The amount of USDN shares to burn.
     * @param currentPriceData The current price data
     * @return securityDepositValue_ The security deposit value
     */
    function _initiateWithdrawal(address user, uint152 usdnShares, bytes calldata currentPriceData)
        internal
        returns (uint256 securityDepositValue_)
    {
        if (usdnShares == 0) {
            revert UsdnProtocolZeroAmount();
        }

        PriceInfo memory currentPrice =
            _getOraclePrice(ProtocolAction.InitiateWithdrawal, block.timestamp, currentPriceData);

        _applyPnlAndFundingAndLiquidate(currentPrice.neutralPrice, currentPrice.timestamp, _liquidationIteration, false);

        // Apply fees on price
        uint128 pendingActionPrice =
            (currentPrice.price + currentPrice.price * _positionFeeBps / BPS_DIVISOR).toUint128();
        uint256 totalExpo = _totalExpo;
        uint256 balanceLong = _balanceLong;
        uint256 balanceVault =
            _vaultAssetAvailable(totalExpo, _balanceVault, balanceLong, pendingActionPrice, _lastPrice).toUint256();

        IUsdn usdn = _usdn;
        _checkImbalanceLimitWithdrawal(
            FixedPointMathLib.fullMulDiv(usdnShares, balanceVault, usdn.totalShares()), totalExpo
        );

        WithdrawalPendingAction memory pendingAction = WithdrawalPendingAction({
            action: ProtocolAction.ValidateWithdrawal,
            timestamp: uint40(block.timestamp),
            user: user,
            securityDepositValue: (_securityDepositValue / SECURITY_DEPOSIT_FACTOR).toUint24(),
            sharesLSB: _calcWithdrawalAmountLSB(usdnShares),
            sharesMSB: _calcWithdrawalAmountMSB(usdnShares),
            assetPrice: pendingActionPrice,
            totalExpo: totalExpo,
            balanceVault: balanceVault,
            balanceLong: balanceLong,
            usdnTotalShares: usdn.totalShares()
        });

        securityDepositValue_ = _addPendingAction(user, _convertWithdrawalPendingAction(pendingAction));

        // retrieve the USDN tokens, checks that balance is sufficient
        usdn.transferSharesFrom(user, address(this), usdnShares);

        emit InitiatedWithdrawal(user, usdn.convertToTokens(usdnShares), block.timestamp);
    }

    function _validateWithdrawal(address user, bytes calldata priceData)
        internal
        returns (uint256 securityDepositValue_)
    {
        PendingAction memory pending = _getAndClearPendingAction(user);

        // check type of action
        if (pending.action != ProtocolAction.ValidateWithdrawal) {
            revert UsdnProtocolInvalidPendingAction();
        }
        // sanity check
        if (pending.user != user) {
            revert UsdnProtocolInvalidPendingAction();
        }

        _validateWithdrawalWithAction(pending, priceData);
        return (pending.securityDepositValue * SECURITY_DEPOSIT_FACTOR);
    }

    function _validateWithdrawalWithAction(PendingAction memory pending, bytes calldata priceData) internal {
        WithdrawalPendingAction memory withdrawal = _toWithdrawalPendingAction(pending);

        PriceInfo memory currentPrice =
            _getOraclePrice(ProtocolAction.ValidateWithdrawal, withdrawal.timestamp, priceData);

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
            _asset.safeTransfer(withdrawal.user, assetToTransfer);
        }

        emit ValidatedWithdrawal(withdrawal.user, assetToTransfer, usdn.convertToTokens(shares), withdrawal.timestamp);
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
     * @param amount The amount of wstETH to deposit.
     * @param desiredLiqPrice The desired liquidation price, including the liquidation penalty.
     * @param currentPriceData  The current price data (used to calculate the temporary leverage and entry price,
     * pending validation)
     * @return posId_ The unique index of the opened position
     * @return securityDepositValue_ The security deposit value
     */
    function _initiateOpenPosition(
        address user,
        uint128 amount,
        uint128 desiredLiqPrice,
        bytes calldata currentPriceData
    ) internal returns (PositionId memory posId_, uint256 securityDepositValue_) {
        if (amount == 0) {
            revert UsdnProtocolZeroAmount();
        }

        uint128 adjustedPrice;
        uint128 neutralPrice;
        {
            PriceInfo memory currentPrice =
                _getOraclePrice(ProtocolAction.InitiateOpenPosition, block.timestamp, currentPriceData);

            // Apply fees on price
            adjustedPrice = (currentPrice.price + (currentPrice.price * _positionFeeBps) / BPS_DIVISOR).toUint128();
            if (FixedPointMathLib.fullMulDiv(amount, adjustedPrice, 10 ** _assetDecimals) < _minLongPosition) {
                revert UsdnProtocolLongPositionTooSmall();
            }

            neutralPrice = currentPrice.neutralPrice.toUint128();

            _applyPnlAndFundingAndLiquidate(
                currentPrice.neutralPrice, currentPrice.timestamp, _liquidationIteration, false
            );
        }

        // we calculate the closest valid tick down for the desired liq price with liquidation penalty
        posId_.tick = getEffectiveTickForPrice(desiredLiqPrice);
        uint8 liquidationPenalty = getTickLiquidationPenalty(posId_.tick);

        (uint128 leverage, uint128 positionTotalExpo) =
            _getOpenPositionLeverage(posId_.tick, liquidationPenalty, adjustedPrice, amount);
        _checkImbalanceLimitOpen(positionTotalExpo, amount);

        {
            // Calculate effective liquidation price
            uint128 liqPrice = getEffectivePriceForTick(posId_.tick);
            // Liquidation price must be at least x% below current price
            _checkSafetyMargin(neutralPrice, liqPrice);
        }

        {
            // Register position and adjust contract state
            Position memory long = Position({
                user: user,
                amount: amount,
                totalExpo: positionTotalExpo,
                timestamp: uint40(block.timestamp)
            });
            (posId_.tickVersion, posId_.index) = _saveNewPosition(posId_.tick, long, liquidationPenalty);
        }

        // Register pending action
        LongPendingAction memory pendingAction = LongPendingAction({
            action: ProtocolAction.ValidateOpenPosition,
            timestamp: uint40(block.timestamp),
            user: user,
            tick: posId_.tick,
            securityDepositValue: (_securityDepositValue / SECURITY_DEPOSIT_FACTOR).toUint24(),
            closeAmount: 0,
            closeTotalExpo: 0,
            tickVersion: posId_.tickVersion,
            index: posId_.index,
            closeLiqMultiplier: 0,
            closeTempTransfer: 0
        });
        securityDepositValue_ = _addPendingAction(user, _convertLongPendingAction(pendingAction));
        emit InitiatedOpenPosition(
            user,
            uint40(block.timestamp),
            leverage,
            amount,
            adjustedPrice,
            posId_.tick,
            posId_.tickVersion,
            posId_.index
        );

        _asset.safeTransferFrom(user, address(this), amount);
    }

    function _validateOpenPosition(address user, bytes calldata priceData)
        internal
        returns (uint256 securityDepositValue_)
    {
        PendingAction memory pending = _getAndClearPendingAction(user);

        // check type of action
        if (pending.action != ProtocolAction.ValidateOpenPosition) {
            revert UsdnProtocolInvalidPendingAction();
        }
        // sanity check
        if (pending.user != user) {
            revert UsdnProtocolInvalidPendingAction();
        }

        _validateOpenPositionWithAction(pending, priceData);
        return (pending.securityDepositValue * SECURITY_DEPOSIT_FACTOR);
    }

    function _validateOpenPositionWithAction(PendingAction memory pending, bytes calldata priceData) internal {
        LongPendingAction memory long = _toLongPendingAction(pending);

        uint128 startPrice;
        {
            PriceInfo memory currentPrice =
                _getOraclePrice(ProtocolAction.ValidateOpenPosition, long.timestamp, priceData);

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
            emit StalePendingActionRemoved(long.user, long.tick, long.tickVersion, long.index);
            return;
        }

        // Get the position
        Position memory pos = _longPositions[tickHash][long.index];
        int24 tickSpacing = _tickSpacing;

        // Re-calculate leverage
        uint128 liqPriceWithoutPenalty =
            getEffectivePriceForTick(long.tick - int24(uint24(_liquidationPenalty)) * tickSpacing);
        // reverts if liquidationPrice >= entryPrice
        uint128 leverage = _getLeverage(startPrice, liqPriceWithoutPenalty);
        // Leverage is always greater than 1 (liquidationPrice is positive).
        // Even if it drops below _minLeverage between the initiate and validate actions, we still allow it.
        // However, if the leverage exceeds max leverage, then we adjust the liquidation price (tick) to have a leverage
        // of _maxLeverage
        if (leverage > _maxLeverage) {
            // remove the position
            _removeAmountFromPosition(long.tick, long.index, pos, pos.amount, pos.totalExpo);
            // theoretical liquidation price for _maxLeverage
            liqPriceWithoutPenalty = _getLiquidationPrice(startPrice, _maxLeverage.toUint128());
            // adjust to closest valid tick down
            int24 tickWithoutPenalty = getEffectiveTickForPrice(liqPriceWithoutPenalty);

            // apply liquidation penalty with the current penalty setting
            uint8 currentLiqPenalty = _liquidationPenalty;
            int24 tick = tickWithoutPenalty + int24(uint24(currentLiqPenalty)) * tickSpacing;
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
                    getEffectivePriceForTick(tick - int24(uint24(liquidationPenalty)) * tickSpacing);
            }
            // recalculate the leverage with the new liquidation price
            leverage = _getLeverage(startPrice, liqPriceWithoutPenalty);
            // update position total expo
            pos.totalExpo = _calculatePositionTotalExpo(pos.amount, startPrice, liqPriceWithoutPenalty);

            // insert position into new tick, update tickVersion and index
            (uint256 tickVersion, uint256 index) = _saveNewPosition(tick, pos, liquidationPenalty);
            // emit LiquidationPriceUpdated
            emit LiquidationPriceUpdated(long.tick, long.tickVersion, long.index, tick, tickVersion, index);
            emit ValidatedOpenPosition(pos.user, leverage, startPrice, tick, tickVersion, index);
        } else {
            // Calculate the new total expo
            uint128 expoBefore = pos.totalExpo;
            uint128 expoAfter = _calculatePositionTotalExpo(pos.amount, startPrice, liqPriceWithoutPenalty);

            // Update the total expo of the position
            _longPositions[tickHash][long.index].totalExpo = expoAfter;
            // Update the total expo by adding the position's new expo and removing the old one.
            // Do not use += or it will underflow
            _totalExpo = _totalExpo + expoAfter - expoBefore;
            _tickData[tickHash].totalExpo = _tickData[tickHash].totalExpo + expoAfter - expoBefore;

            emit ValidatedOpenPosition(long.user, leverage, startPrice, long.tick, long.tickVersion, long.index);
        }
    }

    /**
     * @notice Initiate a close position action.
     * @dev Consult the current oracle middleware implementation to know the expected format for the price data, using
     * the `ProtocolAction.InitiateClosePosition` action.
     * The price validation might require payment according to the return value of the `getValidationCost` function
     * of the middleware.
     * If the current tick version is greater than the tick version of the position (when it was opened), then the
     * position has been liquidated and the transaction will revert.
     * The position is taken out of the tick and put in a pending state during this operation. Thus, calculations don't
     * consider this position anymore. The exit price (and thus profit) is not yet set definitively, and will be done
     * during the validate action.
     * @param user The address of the user initiating the close position.
     * @param posId The unique identifier of the position
     * @param amountToClose The amount of collateral to remove from the position's amount
     * @param currentPriceData The current price data
     * @return securityDepositValue_ The security deposit value
     */
    function _initiateClosePosition(
        address user,
        PositionId memory posId,
        uint128 amountToClose,
        bytes calldata currentPriceData
    ) internal returns (uint256 securityDepositValue_) {
        if (amountToClose == 0) {
            revert UsdnProtocolAmountToCloseIsZero();
        }

        (, uint256 version) = _tickHash(posId.tick);
        if (version != posId.tickVersion) {
            revert UsdnProtocolOutdatedTick(version, posId.tickVersion);
        }

        uint128 priceWithFees;
        {
            PriceInfo memory currentPrice =
                _getOraclePrice(ProtocolAction.InitiateClosePosition, block.timestamp, currentPriceData);

            _applyPnlAndFundingAndLiquidate(
                currentPrice.neutralPrice, currentPrice.timestamp, _liquidationIteration, false
            );

            priceWithFees = (currentPrice.price - (currentPrice.price * _positionFeeBps) / BPS_DIVISOR).toUint128();
        }

        (, version) = _tickHash(posId.tick);
        if (version != posId.tickVersion) {
            // The current tick version doesn't match the version from the position,
            // that means that the position has been liquidated in this transaction.
            return 0;
        }

        (Position memory pos, uint8 liquidationPenalty) = getLongPosition(posId.tick, posId.tickVersion, posId.index);
        // check if the position belongs to the user
        if (pos.user != user) {
            revert UsdnProtocolUnauthorized();
        }

        if (amountToClose > pos.amount) {
            revert UsdnProtocolAmountToCloseHigherThanPositionAmount(amountToClose, pos.amount);
        }

        uint128 totalExpoToClose = (uint256(pos.totalExpo) * amountToClose / pos.amount).toUint128();

        _checkImbalanceLimitClose(totalExpoToClose, amountToClose);

        {
            uint256 liqMultiplier = _liquidationMultiplier;
            (uint256 tempTransfer,) =
                _assetToTransfer(priceWithFees, posId.tick, liquidationPenalty, totalExpoToClose, liqMultiplier, 0);

            LongPendingAction memory pendingAction = LongPendingAction({
                action: ProtocolAction.ValidateClosePosition,
                timestamp: uint40(block.timestamp),
                user: user,
                tick: posId.tick,
                securityDepositValue: (_securityDepositValue / SECURITY_DEPOSIT_FACTOR).toUint24(),
                closeAmount: amountToClose,
                closeTotalExpo: totalExpoToClose,
                tickVersion: posId.tickVersion,
                index: posId.index,
                closeLiqMultiplier: liqMultiplier,
                closeTempTransfer: tempTransfer
            });

            // decrease balance optimistically (exact amount will be recalculated during validation)
            // transfer will be done after validation
            _balanceLong -= tempTransfer;

            securityDepositValue_ = _addPendingAction(user, _convertLongPendingAction(pendingAction));

            // Remove the position if it's fully closed
            _removeAmountFromPosition(posId.tick, posId.index, pos, amountToClose, totalExpoToClose);
        }

        emit InitiatedClosePosition(
            user,
            posId.tick,
            posId.tickVersion,
            posId.index,
            pos.amount - amountToClose,
            pos.totalExpo - totalExpoToClose
        );
    }

    function _validateClosePosition(address user, bytes calldata priceData)
        internal
        returns (uint256 securityDepositValue_)
    {
        PendingAction memory pending = _getAndClearPendingAction(user);

        // check type of action
        if (pending.action != ProtocolAction.ValidateClosePosition) {
            revert UsdnProtocolInvalidPendingAction();
        }
        // sanity check
        if (pending.user != user) {
            revert UsdnProtocolInvalidPendingAction();
        }

        _validateClosePositionWithAction(pending, priceData);
        return (pending.securityDepositValue * SECURITY_DEPOSIT_FACTOR);
    }

    function _validateClosePositionWithAction(PendingAction memory pending, bytes calldata priceData) internal {
        LongPendingAction memory long = _toLongPendingAction(pending);

        PriceInfo memory currentPrice = _getOraclePrice(ProtocolAction.ValidateClosePosition, long.timestamp, priceData);

        _applyPnlAndFundingAndLiquidate(currentPrice.neutralPrice, currentPrice.timestamp, _liquidationIteration, false);

        // Apply fees on price
        uint128 priceWithFees = (currentPrice.price - (currentPrice.price * _positionFeeBps) / BPS_DIVISOR).toUint128();

        (uint256 assetToTransfer, int256 positionValue) = _assetToTransfer(
            priceWithFees,
            long.tick,
            getTickLiquidationPenalty(long.tick),
            long.closeTotalExpo,
            long.closeLiqMultiplier,
            long.closeTempTransfer
        );

        // get liquidation price (with liq penalty) to check if position was valid at `timestamp + validationDelay`
        uint128 liquidationPrice = getEffectivePriceForTick(long.tick, long.closeLiqMultiplier);
        if (currentPrice.neutralPrice <= liquidationPrice) {
            // position should be liquidated, we don't transfer assets to the user.
            // position was already removed from tick so no additional bookkeeping is necessary.
            // restore amount that was optimistically removed.
            int256 tempLongBalance = (_balanceLong + long.closeTempTransfer).toInt256();
            int256 tempVaultBalance = _balanceVault.toInt256();
            // handle any remaining collateral or bad debt.
            tempLongBalance -= positionValue;
            tempVaultBalance += positionValue;
            if (tempLongBalance < 0) {
                tempVaultBalance += tempLongBalance;
                tempLongBalance = 0;
            }
            if (tempVaultBalance < 0) {
                tempLongBalance += tempVaultBalance;
                tempVaultBalance = 0;
            }
            _balanceLong = tempLongBalance.toUint256();
            _balanceVault = tempVaultBalance.toUint256();
            emit LiquidatedPosition(
                long.user, long.tick, long.tickVersion, long.index, currentPrice.neutralPrice, liquidationPrice
            );
            return;
        }

        // adjust long balance that was previously optimistically decreased
        if (assetToTransfer > long.closeTempTransfer) {
            // we didn't remove enough
            // FIXME: here, should we replace assetToTransfer with the user tempTransfer since it's the lower of the
            // two amounts? In which case _balanceLong would already be correct.
            _balanceLong -= assetToTransfer - long.closeTempTransfer;
        } else if (assetToTransfer < long.closeTempTransfer) {
            // we removed too much
            _balanceLong += long.closeTempTransfer - assetToTransfer;
        }

        // send the asset to the user
        if (assetToTransfer > 0) {
            _asset.safeTransfer(long.user, assetToTransfer);
        }

        emit ValidatedClosePosition(
            long.user,
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
     * @param currentPrice The current price of the asset
     * @param tick The tick of the position
     * @param posExpo The total expo of the position
     * @param liqMultiplier The liquidation multiplier at the moment of closing the position
     * @param tempTransferred An amount that was already subtracted from the long balance
     * @return assetToTransfer_ The amount of assets to transfer to the user, bound by zero and the available balance
     * @return positionValue_ The position value, which can be negative in case of bad debt
     */
    function _assetToTransfer(
        uint128 currentPrice,
        int24 tick,
        uint8 liquidationPenalty,
        uint128 posExpo,
        uint256 liqMultiplier,
        uint256 tempTransferred
    ) internal view returns (uint256 assetToTransfer_, int256 positionValue_) {
        // The available amount of asset on the long side
        uint256 available = _balanceLong + tempTransferred;

        // Calculate position value
        positionValue_ = _positionValue(
            currentPrice,
            getEffectivePriceForTick(tick - int24(uint24(liquidationPenalty)) * _tickSpacing, liqMultiplier),
            posExpo
        );

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
        _clearPendingAction(pending.user);
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
        securityDepositValue_ = pending.securityDepositValue * SECURITY_DEPOSIT_FACTOR;
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

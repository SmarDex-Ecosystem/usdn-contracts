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
    VaultPendingAction,
    LongPendingAction,
    PreviousActionsData
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
        _initiateDeposit(msg.sender, amount, currentPriceData);
        _executePendingAction(previousActionsData);
        _refundExcessEther();
        _checkPendingFee();
    }

    /// @inheritdoc IUsdnProtocolActions
    function validateDeposit(bytes calldata depositPriceData, PreviousActionsData calldata previousActionsData)
        external
        payable
        initializedAndNonReentrant
    {
        _validateDeposit(msg.sender, depositPriceData);
        _executePendingAction(previousActionsData);
        _refundExcessEther();
        _checkPendingFee();
    }

    /// @inheritdoc IUsdnProtocolActions
    function initiateWithdrawal(
        uint128 usdnAmount,
        bytes calldata currentPriceData,
        PreviousActionsData calldata previousActionsData
    ) external payable initializedAndNonReentrant {
        _initiateWithdrawal(msg.sender, usdnAmount, currentPriceData);
        _executePendingAction(previousActionsData);
        _refundExcessEther();
        _checkPendingFee();
    }

    /// @inheritdoc IUsdnProtocolActions
    function validateWithdrawal(bytes calldata withdrawalPriceData, PreviousActionsData calldata previousActionsData)
        external
        payable
        initializedAndNonReentrant
    {
        _validateWithdrawal(msg.sender, withdrawalPriceData);
        _executePendingAction(previousActionsData);
        _refundExcessEther();
        _checkPendingFee();
    }

    /// @inheritdoc IUsdnProtocolActions
    function initiateOpenPosition(
        uint128 amount,
        uint128 desiredLiqPrice,
        bytes calldata currentPriceData,
        PreviousActionsData calldata previousActionsData
    ) external payable initializedAndNonReentrant returns (int24 tick_, uint256 tickVersion_, uint256 index_) {
        (tick_, tickVersion_, index_) = _initiateOpenPosition(msg.sender, amount, desiredLiqPrice, currentPriceData);
        _executePendingAction(previousActionsData);
        _refundExcessEther();
        _checkPendingFee();
    }

    /// @inheritdoc IUsdnProtocolActions
    function validateOpenPosition(bytes calldata openPriceData, PreviousActionsData calldata previousActionsData)
        external
        payable
        initializedAndNonReentrant
    {
        _validateOpenPosition(msg.sender, openPriceData);
        _executePendingAction(previousActionsData);
        _refundExcessEther();
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
        _initiateClosePosition(msg.sender, tick, tickVersion, index, amountToClose, currentPriceData);
        _executePendingAction(previousActionsData);
        _refundExcessEther();
        _checkPendingFee();
    }

    /// @inheritdoc IUsdnProtocolActions
    function validateClosePosition(bytes calldata closePriceData, PreviousActionsData calldata previousActionsData)
        external
        payable
        initializedAndNonReentrant
    {
        _validateClosePosition(msg.sender, closePriceData);
        _executePendingAction(previousActionsData);
        _refundExcessEther();
        _checkPendingFee();
    }

    /// @inheritdoc IUsdnProtocolActions
    function liquidate(bytes calldata currentPriceData, uint16 iterations)
        external
        payable
        returns (uint256 liquidatedPositions_)
    {
        liquidatedPositions_ = _liquidate(currentPriceData, iterations);
        _refundExcessEther();
        _checkPendingFee();
    }

    /**
     * @notice The deposit vault imbalance limit state verification
     * @dev To ensure that the protocol does not imbalance more than the deposit limit on vault side
     * @param depositValue the deposit value in asset
     */
    function _imbalanceLimitDeposit(uint256 depositValue) internal view {
        int256 depositExpoImbalanceLimit = _depositExpoImbalanceLimitBps;

        // early return in case limit is disabled
        if (depositExpoImbalanceLimit == 0) {
            return;
        }

        int256 currentLongExpo = _totalExpo.toInt256().safeSub(_balanceLong.toInt256());

        // cannot be calculated
        if (currentLongExpo == 0) {
            revert UsdnProtocolInvalidLongExpo();
        }

        int256 imbalanceBps = ((_balanceVault + depositValue).toInt256().safeSub(currentLongExpo)).safeMul(
            BPS_DIVISOR.toInt256()
        ).safeDiv(currentLongExpo);

        if (imbalanceBps >= depositExpoImbalanceLimit) {
            revert UsdnProtocolImbalanceLimitReached(imbalanceBps);
        }
    }

    /**
     * @notice The withdrawal imbalance limit state verification
     * @dev This is to ensure that the protocol does not imbalance more than the withdrawal limit on long side
     * @param withdrawalValue The withdrawal value in asset
     */
    function _imbalanceLimitWithdrawal(uint256 withdrawalValue) internal view {
        int256 withdrawalExpoImbalanceLimit = _withdrawalExpoImbalanceLimitBps;

        // early return in case limit is disabled
        if (withdrawalExpoImbalanceLimit == 0) {
            return;
        }

        int256 currentVaultExpo = _balanceVault.toInt256();

        // cannot be calculated
        if (currentVaultExpo == 0) {
            revert UsdnProtocolInvalidVaultExpo();
        }

        int256 imbalanceBps = (
            (_totalExpo.toInt256().safeSub(_balanceLong.toInt256())).safeSub(
                currentVaultExpo.safeSub(withdrawalValue.toInt256())
            )
        ).safeMul(BPS_DIVISOR.toInt256()).safeDiv(currentVaultExpo);

        if (imbalanceBps >= withdrawalExpoImbalanceLimit) {
            revert UsdnProtocolImbalanceLimitReached(imbalanceBps);
        }
    }

    /**
     * @notice The open long imbalance limit state verification
     * @dev This is to ensure that the protocol does not imbalance more than the open limit on long side
     * @param openTotalExpoValue The open position expo value
     * @param openCollatValue The open position collateral value
     */
    function _imbalanceLimitOpen(uint256 openTotalExpoValue, uint256 openCollatValue) internal view {
        int256 openExpoImbalanceLimit = _openExpoImbalanceLimitBps;

        // early return in case limit is disabled
        if (openExpoImbalanceLimit == 0) {
            return;
        }

        int256 currentVaultExpo = _balanceVault.toInt256();

        // cannot be calculated
        if (currentVaultExpo == 0) {
            revert UsdnProtocolInvalidVaultExpo();
        }

        int256 imbalanceBps = (
            ((_totalExpo + openTotalExpoValue).toInt256().safeSub((_balanceLong + openCollatValue).toInt256())).safeSub(
                currentVaultExpo
            )
        ).safeMul(BPS_DIVISOR.toInt256()).safeDiv(currentVaultExpo);

        if (imbalanceBps >= openExpoImbalanceLimit) {
            revert UsdnProtocolImbalanceLimitReached(imbalanceBps);
        }
    }

    /**
     * @notice The close vault imbalance limit state verification
     * @dev This is to ensure that the protocol does not imbalance more than the close limit on vault side
     * @param closeTotalExpoValue The close position total expo value
     * @param closeCollatValue The close position collateral value
     */
    function _imbalanceLimitClose(uint256 closeTotalExpoValue, uint256 closeCollatValue) internal view {
        int256 closeExpoImbalanceLimit = _closeExpoImbalanceLimitBps;

        // early return in case limit is disabled
        if (closeExpoImbalanceLimit == 0) {
            return;
        }

        int256 currentLongExpo = _totalExpo.toInt256().safeSub(_balanceLong.toInt256());

        // cannot be calculated
        if (currentLongExpo == 0) {
            revert UsdnProtocolInvalidLongExpo();
        }

        int256 imbalanceBps = (
            _balanceVault.toInt256().safeSub(
                _totalExpo.toInt256().safeSub(closeTotalExpoValue.toInt256()).safeSub(
                    _balanceLong.toInt256().safeSub(closeCollatValue.toInt256())
                )
            )
        ).safeMul(BPS_DIVISOR.toInt256()).safeDiv(currentLongExpo);

        if (imbalanceBps >= closeExpoImbalanceLimit) {
            revert UsdnProtocolImbalanceLimitReached(imbalanceBps);
        }
    }

    /**
     * @notice Send rewards to the liquidator.
     * @dev Should still emit an event if liquidationRewards = 0 to better keep track of those anomalies as rewards for
     * those will be managed off-chain.
     * @param liquidatedTicks The number of ticks that were liquidated.
     * @param liquidatedCollateral The amount of collateral lost due to the liquidations.
     * @param rebased Whether a USDN rebase was performed.
     */
    function _sendRewardsToLiquidator(uint16 liquidatedTicks, int256 liquidatedCollateral, bool rebased) internal {
        // Get how much we should give to the liquidator as rewards
        uint256 liquidationRewards =
            _liquidationRewardsManager.getLiquidationRewards(liquidatedTicks, liquidatedCollateral, rebased);

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
     */
    function _initiateDeposit(address user, uint128 amount, bytes calldata currentPriceData) internal {
        if (amount == 0) {
            revert UsdnProtocolZeroAmount();
        }

        PriceInfo memory currentPrice =
            _getOraclePrice(ProtocolAction.InitiateDeposit, uint40(block.timestamp), currentPriceData);

        _applyPnlAndFundingAndLiquidate(currentPrice.neutralPrice, currentPrice.timestamp);

        // verify deposit imbalance limit
        _imbalanceLimitDeposit(amount);

        // Apply fees on price
        uint128 pendingActionPrice =
            (currentPrice.price - currentPrice.price * _positionFeeBps / BPS_DIVISOR).toUint128();

        VaultPendingAction memory pendingAction = VaultPendingAction({
            action: ProtocolAction.ValidateDeposit,
            timestamp: uint40(block.timestamp),
            user: user,
            _unused: 0,
            amount: amount,
            assetPrice: pendingActionPrice,
            totalExpo: _totalExpo,
            balanceVault: _vaultAssetAvailable(_totalExpo, _balanceVault, _balanceLong, pendingActionPrice, _lastPrice)
                .toUint256(),
            balanceLong: _balanceLong,
            usdnTotalSupply: _usdn.totalSupply()
        });

        _addPendingAction(user, _convertVaultPendingAction(pendingAction));

        _asset.safeTransferFrom(user, address(this), amount);

        emit InitiatedDeposit(user, amount);
    }

    function _validateDeposit(address user, bytes calldata priceData) internal {
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
    }

    function _validateDepositWithAction(PendingAction memory pending, bytes calldata priceData)
        internal
        returns (PriceInfo memory depositPrice_)
    {
        VaultPendingAction memory deposit = _toVaultPendingAction(pending);

        depositPrice_ = _getOraclePrice(ProtocolAction.ValidateDeposit, deposit.timestamp, priceData);

        // adjust balances
        _applyPnlAndFundingAndLiquidate(depositPrice_.neutralPrice, depositPrice_.timestamp);

        // We calculate the amount of USDN to mint, either considering the asset price at the time of the initiate
        // action, or the current price provided for validation. We will use the lower of the two amounts to mint.
        // Apply fees on price
        uint128 priceWithFees =
            (depositPrice_.price - (depositPrice_.price * _positionFeeBps) / BPS_DIVISOR).toUint128();

        uint256 usdnToMint1 =
            _calcMintUsdn(deposit.amount, deposit.balanceVault, deposit.usdnTotalSupply, deposit.assetPrice);

        uint256 usdnToMint2 = _calcMintUsdn(
            deposit.amount,
            // Calculate the available balance in the vault side if the price moves to `priceWithFees`
            uint256(
                _vaultAssetAvailable(
                    deposit.totalExpo, deposit.balanceVault, deposit.balanceLong, priceWithFees, deposit.assetPrice
                )
            ),
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
        emit ValidatedDeposit(deposit.user, deposit.amount, usdnToMint);
    }

    /**
     * @notice Initiate a withdrawal of assets from the vault by providing USDN tokens.
     * @dev Consult the current oracle middleware implementation to know the expected format for the price data, using
     * the `ProtocolAction.InitiateWithdrawal` action.
     * The price validation might require payment according to the return value of the `getValidationCost` function
     * of the middleware.
     * @param user The address of the user initiating the withdrawal.
     * @param usdnAmount The amount of USDN to burn.
     * @param currentPriceData The current price data
     */
    function _initiateWithdrawal(address user, uint128 usdnAmount, bytes calldata currentPriceData) internal {
        if (usdnAmount == 0) {
            revert UsdnProtocolZeroAmount();
        }

        PriceInfo memory currentPrice =
            _getOraclePrice(ProtocolAction.InitiateWithdrawal, uint40(block.timestamp), currentPriceData);

        _applyPnlAndFundingAndLiquidate(currentPrice.neutralPrice, currentPrice.timestamp);

        // Apply fees on price
        uint128 pendingActionPrice =
            (currentPrice.price + currentPrice.price * _positionFeeBps / BPS_DIVISOR).toUint128();
        uint256 totalExpo = _totalExpo;
        uint256 balanceVault =
            _vaultAssetAvailable(totalExpo, _balanceVault, _balanceLong, pendingActionPrice, _lastPrice).toUint256();
        uint256 usdnTotalSupply = _usdn.totalSupply();

        // verify withdrawal imbalance limit
        _imbalanceLimitWithdrawal(FixedPointMathLib.fullMulDiv(usdnAmount, balanceVault, usdnTotalSupply));

        VaultPendingAction memory pendingAction = VaultPendingAction({
            action: ProtocolAction.ValidateWithdrawal,
            timestamp: uint40(block.timestamp),
            user: user,
            _unused: 0,
            amount: usdnAmount,
            assetPrice: pendingActionPrice,
            totalExpo: totalExpo,
            balanceVault: balanceVault,
            balanceLong: _balanceLong,
            usdnTotalSupply: usdnTotalSupply
        });

        _addPendingAction(user, _convertVaultPendingAction(pendingAction));

        // retrieve the USDN tokens, checks that balance is sufficient
        _usdn.safeTransferFrom(user, address(this), usdnAmount);

        emit InitiatedWithdrawal(user, usdnAmount);
    }

    function _validateWithdrawal(address user, bytes calldata priceData) internal {
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
    }

    function _validateWithdrawalWithAction(PendingAction memory pending, bytes calldata priceData) internal {
        VaultPendingAction memory withdrawal = _toVaultPendingAction(pending);

        PriceInfo memory withdrawalPrice =
            _getOraclePrice(ProtocolAction.ValidateWithdrawal, withdrawal.timestamp, priceData);

        _applyPnlAndFundingAndLiquidate(withdrawalPrice.neutralPrice, withdrawalPrice.timestamp);

        // Apply fees on price
        uint128 withdrawalPriceWithFees =
            (withdrawalPrice.price + (withdrawalPrice.price * _positionFeeBps) / BPS_DIVISOR).toUint128();

        // We calculate the available balance of the vault side, either considering the asset price at the time of the
        // initiate action, or the current price provided for validation. We will use the lower of the two amounts to
        // redeem the underlying asset share.
        uint256 available1 = withdrawal.balanceVault;
        uint256 available2 = uint256(
            _vaultAssetAvailable(
                withdrawal.totalExpo,
                withdrawal.balanceVault,
                withdrawal.balanceLong,
                withdrawalPriceWithFees, // new price
                withdrawal.assetPrice // old price
            )
        );
        uint256 available;
        if (available1 <= available2) {
            available = available1;
        } else {
            available = available2;
        }

        // assetToTransfer = amountUsdn * usdnPrice / assetPrice = amountUsdn * assetAvailable / totalSupply
        uint256 assetToTransfer = FixedPointMathLib.fullMulDiv(withdrawal.amount, available, withdrawal.usdnTotalSupply);

        // we have the USDN in the contract already
        _usdn.burn(withdrawal.amount);

        // send the asset to the user
        if (assetToTransfer > 0) {
            _balanceVault -= assetToTransfer;
            _asset.safeTransfer(withdrawal.user, assetToTransfer);
        }

        emit ValidatedWithdrawal(withdrawal.user, assetToTransfer, withdrawal.amount);
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
     */
    function _initiateOpenPosition(
        address user,
        uint128 amount,
        uint128 desiredLiqPrice,
        bytes calldata currentPriceData
    ) internal returns (int24 tick_, uint256 tickVersion_, uint256 index_) {
        if (amount == 0) {
            revert UsdnProtocolZeroAmount();
        }

        uint128 adjustedPrice; // the price returned by the oracle middleware, to be used for the user action
        uint128 neutralPrice;
        {
            PriceInfo memory currentPrice =
                _getOraclePrice(ProtocolAction.InitiateOpenPosition, uint40(block.timestamp), currentPriceData);

            // Apply fees on price
            adjustedPrice = (currentPrice.price + (currentPrice.price * _positionFeeBps) / BPS_DIVISOR).toUint128();

            neutralPrice = currentPrice.neutralPrice.toUint128();

            _applyPnlAndFundingAndLiquidate(neutralPrice, currentPrice.timestamp);
        }

        uint128 leverage;
        uint128 positionTotalExpo;
        {
            // we calculate the closest valid tick down for the desired liq price with liquidation penalty
            tick_ = getEffectiveTickForPrice(desiredLiqPrice);

            // remove liquidation penalty for leverage calculation
            uint128 liqPriceWithoutPenalty = getEffectivePriceForTick(tick_ - int24(_liquidationPenalty) * _tickSpacing);
            positionTotalExpo = _calculatePositionTotalExpo(amount, adjustedPrice, liqPriceWithoutPenalty);
            // verify open imbalance limit
            _imbalanceLimitOpen(positionTotalExpo, amount);
            // calculate position leverage
            // reverts if liquidationPrice >= entryPrice
            leverage = _getLeverage(adjustedPrice, liqPriceWithoutPenalty);
            if (leverage < _minLeverage) {
                revert UsdnProtocolLeverageTooLow();
            }
            if (leverage > _maxLeverage) {
                revert UsdnProtocolLeverageTooHigh();
            }
        }

        {
            // Calculate effective liquidation price
            uint128 liqPrice = getEffectivePriceForTick(tick_);
            // Liquidation price must be at least x% below current price
            _checkSafetyMargin(neutralPrice, liqPrice);
        }

        // Register position and adjust contract state
        {
            Position memory long = Position({
                user: user,
                amount: amount,
                totalExpo: positionTotalExpo,
                timestamp: uint40(block.timestamp)
            });
            (tickVersion_, index_) = _saveNewPosition(tick_, long);

            // Register pending action
            LongPendingAction memory pendingAction = LongPendingAction({
                action: ProtocolAction.ValidateOpenPosition,
                timestamp: uint40(block.timestamp),
                user: user,
                tick: tick_,
                closeAmount: 0,
                closeTotalExpo: 0,
                tickVersion: tickVersion_,
                index: index_,
                closeLiqMultiplier: 0,
                closeTempTransfer: 0
            });
            _addPendingAction(user, _convertLongPendingAction(pendingAction));
            emit InitiatedOpenPosition(
                user, long.timestamp, leverage, long.amount, adjustedPrice, tick_, tickVersion_, index_
            );
        }
        _asset.safeTransferFrom(user, address(this), amount);
    }

    function _validateOpenPosition(address user, bytes calldata priceData) internal {
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
    }

    function _validateOpenPositionWithAction(PendingAction memory pending, bytes calldata priceData) internal {
        LongPendingAction memory long = _toLongPendingAction(pending);

        uint128 startPrice;
        {
            PriceInfo memory price = _getOraclePrice(ProtocolAction.ValidateOpenPosition, long.timestamp, priceData);

            // Apply fees on price
            startPrice = (price.price + (price.price * _positionFeeBps) / BPS_DIVISOR).toUint128();

            _applyPnlAndFundingAndLiquidate(price.neutralPrice, price.timestamp);
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
        // Re-calculate leverage
        uint128 liqPriceWithoutPenalty = getEffectivePriceForTick(long.tick - int24(_liquidationPenalty) * _tickSpacing);
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
            // retrieve exact liquidation price without penalty
            liqPriceWithoutPenalty = getEffectivePriceForTick(tickWithoutPenalty);
            // recalculate the leverage with the new liquidation price
            leverage = _getLeverage(startPrice, liqPriceWithoutPenalty);
            // update position total expo
            pos.totalExpo = _calculatePositionTotalExpo(pos.amount, startPrice, liqPriceWithoutPenalty);
            // apply liquidation penalty
            int24 tick = tickWithoutPenalty + int24(_liquidationPenalty) * _tickSpacing;
            // insert position into new tick, update tickVersion and index
            (uint256 tickVersion, uint256 index) = _saveNewPosition(tick, pos);
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
            _totalExpoByTick[tickHash] = _totalExpoByTick[tickHash] + expoAfter - expoBefore;

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
     * @param tick The tick containing the position to close
     * @param tickVersion The tick version of the position to close
     * @param index The index of the position inside the tick array
     * @param amountToClose The amount of collateral to remove from the position's amount
     * @param currentPriceData The current price data
     */
    function _initiateClosePosition(
        address user,
        int24 tick,
        uint256 tickVersion,
        uint256 index,
        uint128 amountToClose,
        bytes calldata currentPriceData
    ) internal {
        // check if the position belongs to the user
        // this reverts if the position was liquidated
        Position memory pos = getLongPosition(tick, tickVersion, index);
        if (pos.user != user) {
            revert UsdnProtocolUnauthorized();
        }

        if (amountToClose > pos.amount) {
            revert UsdnProtocolAmountToCloseHigherThanPositionAmount(amountToClose, pos.amount);
        }

        if (amountToClose == 0) {
            revert UsdnProtocolAmountToCloseIsZero();
        }

        uint128 priceWithFees;
        {
            PriceInfo memory currentPrice =
                _getOraclePrice(ProtocolAction.InitiateClosePosition, uint40(block.timestamp), currentPriceData);

            _applyPnlAndFundingAndLiquidate(currentPrice.neutralPrice, currentPrice.timestamp);

            priceWithFees = (currentPrice.price - (currentPrice.price * _positionFeeBps) / BPS_DIVISOR).toUint128();
        }

        uint128 totalExpoToClose = (uint256(pos.totalExpo) * amountToClose / pos.amount).toUint128();

        // verify withdrawal imbalance limit
        _imbalanceLimitClose(totalExpoToClose, amountToClose);

        {
            uint256 liqMultiplier = _liquidationMultiplier;
            uint256 tempTransfer = _assetToTransfer(priceWithFees, tick, totalExpoToClose, liqMultiplier, 0);

            LongPendingAction memory pendingAction = LongPendingAction({
                action: ProtocolAction.ValidateClosePosition,
                timestamp: uint40(block.timestamp),
                user: user,
                tick: tick,
                closeAmount: amountToClose,
                closeTotalExpo: totalExpoToClose,
                tickVersion: tickVersion,
                index: index,
                closeLiqMultiplier: liqMultiplier,
                closeTempTransfer: tempTransfer
            });

            // decrease balance optimistically (exact amount will be recalculated during validation)
            // transfer will be done after validation
            _balanceLong -= tempTransfer;

            _addPendingAction(user, _convertLongPendingAction(pendingAction));

            // Remove the position if it's fully closed
            _removeAmountFromPosition(tick, index, pos, amountToClose, totalExpoToClose);
        }

        emit InitiatedClosePosition(
            user, tick, tickVersion, index, pos.amount - amountToClose, pos.totalExpo - totalExpoToClose
        );
    }

    function _validateClosePosition(address user, bytes calldata priceData) internal {
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
    }

    function _validateClosePositionWithAction(PendingAction memory pending, bytes calldata priceData) internal {
        LongPendingAction memory long = _toLongPendingAction(pending);

        PriceInfo memory price = _getOraclePrice(ProtocolAction.ValidateClosePosition, long.timestamp, priceData);

        _applyPnlAndFundingAndLiquidate(price.neutralPrice, price.timestamp);

        // Apply fees on price
        uint128 priceWithFees = (price.price - (price.price * _positionFeeBps) / BPS_DIVISOR).toUint128();

        uint256 assetToTransfer = _assetToTransfer(
            priceWithFees, long.tick, long.closeTotalExpo, long.closeLiqMultiplier, long.closeTempTransfer
        );

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

        // get liquidation price (with liq penalty) to check if position was valid at `timestamp + validationDelay`
        uint128 liquidationPrice = getEffectivePriceForTick(long.tick, long.closeLiqMultiplier);
        if (price.neutralPrice <= liquidationPrice) {
            // position should be liquidated, we don't pay out the profits but send any remaining collateral to the
            // vault
            _balanceVault += assetToTransfer;
            emit LiquidatedPosition(
                long.user, long.tick, long.tickVersion, long.index, price.neutralPrice, liquidationPrice
            );
            return;
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
     * @notice Liquidate positions according to the current asset price, limited to a maximum of `iterations` ticks.
     * @dev Consult the current oracle middleware implementation to know the expected format for the price data, using
     * the `ProtocolAction.Liquidation` action.
     * The price validation might require payment according to the return value of the `getValidationCost` function
     * of the middleware.
     * Each tick is liquidated in constant time. The tick version is incremented for each tick that was liquidated.
     * At least one tick will be liquidated, even if the `iterations` parameter is zero.
     * @param currentPriceData The most recent price data
     * @param iterations The maximum number of ticks to liquidate
     * @return liquidatedPositions_ The number of positions that were liquidated
     */
    function _liquidate(bytes calldata currentPriceData, uint16 iterations)
        internal
        returns (uint256 liquidatedPositions_)
    {
        PriceInfo memory currentPrice =
            _getOraclePrice(ProtocolAction.Liquidation, uint40(block.timestamp), currentPriceData);

        (, int256 tempLongBalance, int256 tempVaultBalance) =
            _applyPnlAndFunding(currentPrice.neutralPrice.toUint128(), currentPrice.timestamp.toUint128());

        uint16 liquidatedTicks;
        int256 liquidatedCollateral;
        (liquidatedPositions_, liquidatedTicks, liquidatedCollateral, _balanceLong, _balanceVault) =
            _liquidatePositions(currentPrice.neutralPrice, iterations, tempLongBalance, tempVaultBalance);

        // Always perform the rebase check during liquidation
        bool rebased = _usdnRebase(uint128(currentPrice.neutralPrice), true); // SafeCast not needed since done above

        if (liquidatedTicks > 0) {
            _sendRewardsToLiquidator(liquidatedTicks, liquidatedCollateral, rebased);
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
     */
    function _assetToTransfer(
        uint128 currentPrice,
        int24 tick,
        uint128 posExpo,
        uint256 liqMultiplier,
        uint256 tempTransferred
    ) internal view returns (uint256 assetToTransfer_) {
        // The available amount of asset on the long side
        uint256 available = _balanceLong + tempTransferred;

        // Calculate position value
        uint256 value = _positionValue(
            currentPrice,
            getEffectivePriceForTick(tick - int24(_liquidationPenalty) * _tickSpacing, liqMultiplier),
            posExpo
        );

        if (value > available) {
            assetToTransfer_ = available;
        } else {
            assetToTransfer_ = value;
        }
    }

    function _executePendingAction(PreviousActionsData calldata data) internal {
        (PendingAction memory pending, uint128 rawIndex) = _getActionablePendingAction();
        if (pending.action == ProtocolAction.None) {
            // no pending action
            return;
        }
        uint256 length = data.priceData.length;
        if (data.rawIndices.length != length || length < 1) {
            revert UsdnProtocolInvalidPendingActionData();
        }
        uint128 offset;
        unchecked {
            // underflow is desired here (wrap-around)
            offset = rawIndex - data.rawIndices[0];
        }
        if (offset >= length || data.rawIndices[offset] != rawIndex) {
            revert UsdnProtocolInvalidPendingActionData();
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
    }

    function _getOraclePrice(ProtocolAction action, uint40 timestamp, bytes calldata priceData)
        internal
        returns (PriceInfo memory price_)
    {
        uint256 validationCost = _oracleMiddleware.validationCost(priceData, action);
        if (address(this).balance < validationCost) {
            revert UsdnProtocolInsufficientOracleFee();
        }
        price_ = _oracleMiddleware.parseAndValidatePrice{ value: validationCost }(timestamp, action, priceData);
    }

    function _applyPnlAndFundingAndLiquidate(uint256 neutralPrice, uint256 timestamp) internal {
        // adjust balances
        (bool priceUpdated, int256 tempLongBalance, int256 tempVaultBalance) =
            _applyPnlAndFunding(neutralPrice.toUint128(), timestamp.toUint128());
        // liquidate if price is more recent than _lastPrice
        if (priceUpdated) {
            (,,, _balanceLong, _balanceVault) =
                _liquidatePositions(neutralPrice, _liquidationIteration, tempLongBalance, tempVaultBalance);
            // rebase USDN if needed (interval has elapsed and price threshold was reached)
            _usdnRebase(uint128(neutralPrice), false); // safecast not needed since already done earlier
        }
    }

    /// @notice Refund any excess ether to the user, making sure we don't lock ETH in the contract.
    function _refundExcessEther() internal {
        if (address(this).balance > 0) {
            (bool success,) = payable(msg.sender).call{ value: address(this).balance }("");
            if (!success) {
                revert UsdnProtocolEtherRefundFailed();
            }
        }
    }

    function _checkPendingFee() internal {
        // if pending protocol fee is above threshold, send it to the fee collector
        if (_pendingProtocolFee >= _feeThreshold) {
            _asset.safeTransfer(_feeCollector, _pendingProtocolFee);
            emit ProtocolFeeDistributed(_feeCollector, _pendingProtocolFee);
            _pendingProtocolFee = 0;
        }
    }
}

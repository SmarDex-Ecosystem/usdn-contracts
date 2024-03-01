// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { FixedPointMathLib } from "solady/src/utils/FixedPointMathLib.sol";
import { LibBitmap } from "solady/src/utils/LibBitmap.sol";

import { IUsdnProtocolActions } from "src/interfaces/UsdnProtocol/IUsdnProtocolActions.sol";
import {
    Position,
    ProtocolAction,
    PendingAction,
    VaultPendingAction,
    LongPendingAction
} from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import { UsdnProtocolLong } from "src/UsdnProtocol/UsdnProtocolLong.sol";
import { PriceInfo } from "src/interfaces/OracleMiddleware/IOracleMiddlewareTypes.sol";
import { IUsdn } from "src/interfaces/Usdn/IUsdn.sol";

abstract contract UsdnProtocolActions is IUsdnProtocolActions, UsdnProtocolLong {
    using SafeERC20 for IERC20Metadata;
    using SafeERC20 for IUsdn;
    using SafeERC20 for IERC20Metadata;
    using SafeCast for uint256;
    using LibBitmap for LibBitmap.Bitmap;

    /// @inheritdoc IUsdnProtocolActions
    uint256 public constant MIN_USDN_SUPPLY = 1000;

    /// @inheritdoc IUsdnProtocolActions
    function initiateDeposit(uint128 amount, bytes calldata currentPriceData, bytes calldata previousActionPriceData)
        external
        payable
        initializedAndNonReentrant
    {
        if (amount == 0) {
            revert UsdnProtocolZeroAmount();
        }

        PriceInfo memory currentPrice =
            _getOraclePrice(ProtocolAction.InitiateDeposit, uint40(block.timestamp), currentPriceData);

        _applyPnlAndFundingAndLiquidate(currentPrice.neutralPrice, currentPrice.timestamp);

        VaultPendingAction memory pendingAction = VaultPendingAction({
            action: ProtocolAction.ValidateDeposit,
            timestamp: uint40(block.timestamp),
            user: msg.sender,
            _unused: 0,
            amount: amount,
            assetPrice: _lastPrice, // we use `_lastPrice` because it might be more recent than currentPriceData
            totalExpo: _totalExpo,
            balanceVault: _balanceVault,
            balanceLong: _balanceLong,
            usdnTotalSupply: _usdn.totalSupply()
        });

        _addPendingAction(msg.sender, _convertVaultPendingAction(pendingAction));

        _asset.safeTransferFrom(msg.sender, address(this), amount);

        emit InitiatedDeposit(msg.sender, amount);
        _executePendingAction(previousActionPriceData);
        _refundExcessEther();
        _checkPendingFee();
    }

    /// @inheritdoc IUsdnProtocolActions
    function validateDeposit(bytes calldata depositPriceData, bytes calldata previousActionPriceData)
        external
        payable
        initializedAndNonReentrant
    {
        _validateDeposit(msg.sender, depositPriceData);
        _executePendingAction(previousActionPriceData);
        _refundExcessEther();
        _checkPendingFee();
    }

    /// @inheritdoc IUsdnProtocolActions
    function initiateWithdrawal(
        uint128 usdnAmount,
        bytes calldata currentPriceData,
        bytes calldata previousActionPriceData
    ) external payable initializedAndNonReentrant {
        if (usdnAmount == 0) {
            revert UsdnProtocolZeroAmount();
        }

        PriceInfo memory currentPrice =
            _getOraclePrice(ProtocolAction.InitiateWithdrawal, uint40(block.timestamp), currentPriceData);

        _applyPnlAndFundingAndLiquidate(currentPrice.neutralPrice, currentPrice.timestamp);

        VaultPendingAction memory pendingAction = VaultPendingAction({
            action: ProtocolAction.ValidateWithdrawal,
            timestamp: uint40(block.timestamp),
            user: msg.sender,
            _unused: 0,
            amount: usdnAmount,
            assetPrice: _lastPrice, // we use `_lastPrice` because it might be more recent than currentPriceData
            totalExpo: _totalExpo,
            balanceVault: _balanceVault,
            balanceLong: _balanceLong,
            usdnTotalSupply: _usdn.totalSupply()
        });

        _addPendingAction(msg.sender, _convertVaultPendingAction(pendingAction));

        // retrieve the USDN tokens, checks that balance is sufficient
        _usdn.safeTransferFrom(msg.sender, address(this), usdnAmount);

        emit InitiatedWithdrawal(msg.sender, usdnAmount);

        _executePendingAction(previousActionPriceData);
        _refundExcessEther();
        _checkPendingFee();
    }

    /// @inheritdoc IUsdnProtocolActions
    function validateWithdrawal(bytes calldata withdrawalPriceData, bytes calldata previousActionPriceData)
        external
        payable
        initializedAndNonReentrant
    {
        _validateWithdrawal(msg.sender, withdrawalPriceData);
        _executePendingAction(previousActionPriceData);
        _refundExcessEther();
        _checkPendingFee();
    }

    /// @inheritdoc IUsdnProtocolActions
    function initiateOpenPosition(
        uint96 amount,
        uint128 desiredLiqPrice,
        bytes calldata currentPriceData,
        bytes calldata previousActionPriceData
    ) external payable initializedAndNonReentrant returns (int24 tick_, uint256 tickVersion_, uint256 index_) {
        if (amount == 0) {
            revert UsdnProtocolZeroAmount();
        }

        uint128 adjustedPrice; // the price returned by the oracle middleware, to be used for the user action
        uint128 neutralPrice;
        {
            PriceInfo memory currentPrice =
                _getOraclePrice(ProtocolAction.InitiateOpenPosition, uint40(block.timestamp), currentPriceData);

            adjustedPrice = currentPrice.price.toUint128();
            neutralPrice = currentPrice.neutralPrice.toUint128();

            _applyPnlAndFundingAndLiquidate(neutralPrice, currentPrice.timestamp);
        }

        uint128 leverage;
        {
            // we calculate the closest valid tick down for the desired liq price with liquidation penalty
            tick_ = getEffectiveTickForPrice(desiredLiqPrice);

            // remove liquidation penalty for leverage calculation
            uint128 liqPriceWithoutPenalty = getEffectivePriceForTick(tick_ - int24(_liquidationPenalty) * _tickSpacing);

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

        uint128 positionExpo;
        {
            // Calculate effective liquidation price
            uint128 liquidationPrice = getEffectivePriceForTick(tick_);

            // Liquidation price must be at least x% below current price
            _checkSafetyMargin(neutralPrice, liquidationPrice);
            positionExpo = _calculatePositionExpo(amount, adjustedPrice, liquidationPrice);
        }

        // Register position and adjust contract state
        {
            Position memory long =
                Position({ user: msg.sender, amount: amount, expo: positionExpo, timestamp: uint40(block.timestamp) });
            (tickVersion_, index_) = _saveNewPosition(tick_, long);

            // Register pending action
            LongPendingAction memory pendingAction = LongPendingAction({
                action: ProtocolAction.ValidateOpenPosition,
                timestamp: uint40(block.timestamp),
                user: msg.sender,
                tick: tick_,
                closeAmount: 0,
                expo: long.expo,
                tickVersion: tickVersion_,
                index: index_,
                closeLiqMultiplier: 0,
                closeTempTransfer: 0
            });
            _addPendingAction(msg.sender, _convertLongPendingAction(pendingAction));
            emit InitiatedOpenPosition(
                msg.sender, long.timestamp, leverage, long.amount, adjustedPrice, tick_, tickVersion_, index_
            );
        }
        _asset.safeTransferFrom(msg.sender, address(this), amount);

        _executePendingAction(previousActionPriceData);
        _refundExcessEther();
        _checkPendingFee();
    }

    /// @inheritdoc IUsdnProtocolActions
    function validateOpenPosition(bytes calldata openPriceData, bytes calldata previousActionPriceData)
        external
        payable
        initializedAndNonReentrant
    {
        _validateOpenPosition(msg.sender, openPriceData);
        _executePendingAction(previousActionPriceData);
        _refundExcessEther();
        _checkPendingFee();
    }

    /// @inheritdoc IUsdnProtocolActions
    function initiateClosePosition(
        int24 tick,
        uint256 tickVersion,
        uint256 index,
        bytes calldata currentPriceData,
        bytes calldata previousActionPriceData
    ) external payable initializedAndNonReentrant {
        // check if the position belongs to the user
        // this reverts if the position was liquidated
        Position memory pos = getLongPosition(tick, tickVersion, index);
        if (pos.user != msg.sender) {
            revert UsdnProtocolUnauthorized();
        }

        PriceInfo memory currentPrice =
            _getOraclePrice(ProtocolAction.InitiateClosePosition, uint40(block.timestamp), currentPriceData);

        _applyPnlAndFundingAndLiquidate(currentPrice.neutralPrice, currentPrice.timestamp);

        {
            uint256 liqMultiplier = _liquidationMultiplier;
            uint256 tempTransfer = _assetToTransfer(currentPrice.price.toUint128(), tick, pos.expo, liqMultiplier);

            LongPendingAction memory pendingAction = LongPendingAction({
                action: ProtocolAction.ValidateClosePosition,
                timestamp: uint40(block.timestamp),
                user: msg.sender,
                tick: tick,
                expo: pos.expo,
                closeAmount: pos.amount,
                tickVersion: tickVersion,
                index: index,
                closeLiqMultiplier: liqMultiplier,
                closeTempTransfer: tempTransfer
            });

            // decrease balance optimistically (exact amount will be recalculated during validation)
            // transfer will be done after validation
            _balanceLong -= tempTransfer;

            _addPendingAction(msg.sender, _convertLongPendingAction(pendingAction));
        }

        _removePosition(tick, tickVersion, index);

        emit InitiatedClosePosition(msg.sender, tick, tickVersion, index);

        _executePendingAction(previousActionPriceData);
        _refundExcessEther();
        _checkPendingFee();
    }

    /// @inheritdoc IUsdnProtocolActions
    function validateClosePosition(bytes calldata closePriceData, bytes calldata previousActionPriceData)
        external
        payable
        initializedAndNonReentrant
    {
        _validateClosePosition(msg.sender, closePriceData);
        _executePendingAction(previousActionPriceData);
        _refundExcessEther();
        _checkPendingFee();
    }

    /// @inheritdoc IUsdnProtocolActions
    function liquidate(bytes calldata currentPriceData, uint16 iterations)
        external
        payable
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

        _refundExcessEther();
        _checkPendingFee();

        if (liquidatedTicks > 0) {
            _sendRewardsToLiquidator(liquidatedTicks, liquidatedCollateral);
        }
    }

    /**
     * @notice Send rewards to the liquidator.
     * @dev Should still emit an event if liquidationRewards = 0 to better keep track of those anomalies as rewards for
     * those will be managed off-chain.
     * @param liquidatedTicks The number of ticks that were liquidated.
     * @param liquidatedCollateral The amount of collateral lost due to the liquidations.
     */
    function _sendRewardsToLiquidator(uint16 liquidatedTicks, int256 liquidatedCollateral) internal {
        // Get how much we should give to the liquidator as rewards
        uint256 liquidationRewards =
            _liquidationRewardsManager.getLiquidationRewards(liquidatedTicks, liquidatedCollateral);

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

        _validateDepositWithAction(pending, priceData, false);
    }

    function _validateDepositWithAction(PendingAction memory pending, bytes calldata priceData, bool initializing)
        internal
        returns (PriceInfo memory depositPrice_)
    {
        VaultPendingAction memory deposit = _toVaultPendingAction(pending);

        // During initialization, we might want to use a different oracle, so we have a special action
        ProtocolAction action = initializing ? ProtocolAction.Initialize : ProtocolAction.ValidateDeposit;

        depositPrice_ = _getOraclePrice(action, deposit.timestamp, priceData);

        // adjust balances
        if (!initializing) {
            // There is no need to adjust balances during initialization.
            // Also, during initialization, `_lastUpdateTimestamp` and `_lastPrice` are not updated yet.

            _applyPnlAndFundingAndLiquidate(depositPrice_.neutralPrice, depositPrice_.timestamp);
        }

        // We calculate the amount of USDN to mint, either considering the asset price at the time of the initiate
        // action, or the current price provided for validation. We will use the lower of the two amounts to mint.

        // During initialization, the deposit.assetPrice is zero, so we use the price provided for validation.
        uint256 oldPrice = initializing ? depositPrice_.price : deposit.assetPrice;

        // The last parameter (price) is only used during initialization
        uint256 usdnToMint1 = _calcMintUsdn(deposit.amount, deposit.balanceVault, deposit.usdnTotalSupply, oldPrice);
        uint256 usdnToMint2 = _calcMintUsdn(
            deposit.amount,
            uint256(
                _vaultAssetAvailable(
                    deposit.totalExpo,
                    deposit.balanceVault,
                    deposit.balanceLong,
                    depositPrice_.price.toUint128(), // new price
                    deposit.assetPrice // old price
                )
            ),
            deposit.usdnTotalSupply,
            depositPrice_.price
        );
        uint256 usdnToMint;
        if (usdnToMint1 <= usdnToMint2) {
            usdnToMint = usdnToMint1;
        } else {
            usdnToMint = usdnToMint2;
        }

        _balanceVault += deposit.amount;

        if (initializing) {
            // we mint the minimum amount of USDN to the dead address, so that the total supply never falls to zero
            _usdn.mint(DEAD_ADDRESS, MIN_USDN_SUPPLY);
            uint256 mintToUser = usdnToMint - MIN_USDN_SUPPLY;
            _usdn.mint(deposit.user, mintToUser);
            emit ValidatedDeposit(DEAD_ADDRESS, 0, MIN_USDN_SUPPLY);
            emit ValidatedDeposit(deposit.user, deposit.amount, mintToUser);
        } else {
            _usdn.mint(deposit.user, usdnToMint);
            emit ValidatedDeposit(deposit.user, deposit.amount, usdnToMint);
        }
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

        // We calculate the available balance of the vault side, either considering the asset price at the time of the
        // initiate action, or the current price provided for validation. We will use the lower of the two amounts to
        // redeem the underlying asset share.

        uint256 available1 = withdrawal.balanceVault;
        uint256 available2 = uint256(
            _vaultAssetAvailable(
                withdrawal.totalExpo,
                withdrawal.balanceVault,
                withdrawal.balanceLong,
                withdrawalPrice.price.toUint128(), // new price
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

            startPrice = price.price.toUint128();

            _applyPnlAndFundingAndLiquidate(price.neutralPrice, price.timestamp);
        }

        (bytes32 tickHash, uint256 version) = _tickHash(long.tick);
        if (version != long.tickVersion) {
            // The current tick version doesn't match the version from the pending action.
            // This means the position has been liquidated in the mean time
            emit StalePendingActionRemoved(long.user, long.tick, long.tickVersion, long.index);
            return;
        }

        // Re-calculate leverage
        uint128 liqPriceWithoutPenalty = getEffectivePriceForTick(long.tick - int24(_liquidationPenalty) * _tickSpacing);
        // reverts if liquidationPrice >= entryPrice
        uint128 leverage = _getLeverage(startPrice, liqPriceWithoutPenalty);
        // Leverage is always greater than 1 (liquidationPrice is positive).
        // Even if it drops below _minLeverage between the initiate and validate actions, we still allow it.
        // However, if the leverage exceeds max leverage, then we adjust the liquidation price (tick) to have a leverage
        // of _maxLeverage
        if (leverage > _maxLeverage) {
            // remove and retrieve position
            Position memory pos = _removePosition(long.tick, long.tickVersion, long.index);
            // theoretical liquidation price for _maxLeverage
            liqPriceWithoutPenalty = _getLiquidationPrice(startPrice, _maxLeverage.toUint128());
            // adjust to closest valid tick down
            int24 tickWithoutPenalty = getEffectiveTickForPrice(liqPriceWithoutPenalty);
            // retrieve exact liquidation price without penalty
            liqPriceWithoutPenalty = getEffectivePriceForTick(tickWithoutPenalty);
            // update position expo
            pos.expo = _calculatePositionExpo(pos.amount, startPrice, liqPriceWithoutPenalty);
            // apply liquidation penalty
            int24 tick = tickWithoutPenalty + int24(_liquidationPenalty) * _tickSpacing;
            // insert position into new tick, update tickVersion and index
            (uint256 tickVersion, uint256 index) = _saveNewPosition(tick, pos);
            // emit LiquidationPriceUpdated
            emit LiquidationPriceUpdated(long.tick, long.tickVersion, long.index, tick, tickVersion, index);
            emit ValidatedOpenPosition(pos.user, leverage, startPrice, tick, tickVersion, index);
        } else {
            Position storage pos = _longPositions[tickHash][long.index];
            // Calculate the new total expo
            uint128 expoBefore = pos.expo;
            uint128 expoAfter = _calculatePositionExpo(pos.amount, startPrice, liqPriceWithoutPenalty);

            // Update the expo of the position
            pos.expo = expoAfter;
            // Update the total expo by adding the position's new expo and removing the old one.
            // Do not use += or it will underflow
            _totalExpo = _totalExpo + expoAfter - expoBefore;
            _totalExpoByTick[tickHash] = _totalExpoByTick[tickHash] + expoAfter - expoBefore;

            emit ValidatedOpenPosition(long.user, leverage, startPrice, long.tick, long.tickVersion, long.index);
        }
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

        uint256 assetToTransfer =
            _assetToTransfer(price.price.toUint128(), long.tick, long.expo, long.closeLiqMultiplier);

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
            int256(assetToTransfer) - _toInt256(long.closeAmount)
        );
    }

    /**
     * @notice Calculate how much wstETH must be transferred to a user to close a position.
     * @dev The amount is bound by the amount of wstETH available in the long side.
     * @param currentPrice The current price
     * @param posTick The tick of the position
     * @param posExpo The expo of the position
     * @param liqMultiplier The liquidation multiplier at the moment of closing the position
     */
    function _assetToTransfer(uint128 currentPrice, int24 posTick, uint128 posExpo, uint256 liqMultiplier)
        internal
        view
        returns (uint256 assetToTransfer_)
    {
        // calculate amount to transfer
        int256 available = _longAssetAvailable(currentPrice);
        if (available <= 0) {
            return 0;
        }

        // Calculate position value
        int256 value = _positionValue(
            currentPrice,
            getEffectivePriceForTick(posTick - int24(_liquidationPenalty) * _tickSpacing, liqMultiplier),
            posExpo
        ).toInt256();

        if (value > available) {
            assetToTransfer_ = uint256(available);
        } else {
            assetToTransfer_ = uint256(value);
        }
    }

    function _executePendingAction(bytes calldata priceData) internal {
        PendingAction memory pending = _getActionablePendingAction(0); // use default maxIter
        if (pending.action == ProtocolAction.None) {
            // no pending action
            return;
        }
        _clearPendingAction(pending.user);
        if (pending.action == ProtocolAction.ValidateDeposit) {
            _validateDepositWithAction(pending, priceData, false);
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

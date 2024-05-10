// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { LibBitmap } from "solady/src/utils/LibBitmap.sol";
import { FixedPointMathLib } from "solady/src/utils/FixedPointMathLib.sol";

import { Position, LiquidationsEffects, TickData, PositionId } from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import { TickMath } from "src/libraries/TickMath.sol";
import { SignedMath } from "src/libraries/SignedMath.sol";
import { HugeUint } from "src/libraries/HugeUint.sol";
import { PriceInfo } from "src/interfaces/OracleMiddleware/IOracleMiddlewareTypes.sol";

import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { LibBitmap } from "solady/src/utils/LibBitmap.sol";
import { FixedPointMathLib } from "solady/src/utils/FixedPointMathLib.sol";

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
import { UsdnProtocolCommon } from "src/UsdnProtocol/UsdnProtocolCommon.sol";
import { IUsdn } from "src/interfaces/Usdn/IUsdn.sol";
import { TickMath } from "src/libraries/TickMath.sol";
import { SignedMath } from "src/libraries/SignedMath.sol";
import { HugeUint } from "src/libraries/HugeUint.sol";

abstract contract UsdnProtocolLongProxy is UsdnProtocolCommon {
    using SafeERC20 for IERC20Metadata;
    using SafeERC20 for IUsdn;
    using SafeCast for uint256;
    using SafeCast for int256;
    using LibBitmap for LibBitmap.Bitmap;
    using SignedMath for int256;
    using HugeUint for HugeUint.Uint512;

    /**
     * @dev Structure to hold the transient data during `_initiateClosePosition`
     * @param pos The position to close
     * @param liquidationPenalty The liquidation penalty
     * @param securityDepositValue The security deposit value
     * @param totalExpoToClose The total expo to close
     * @param lastPrice The price after the last balances update
     * @param tempPositionValue The bounded value of the position that was removed from the long balance
     * @param longTradingExpo The long trading expo
     * @param liqMulAcc The liquidation multiplier accumulator
     */
    struct ClosePositionData {
        Position pos;
        uint8 liquidationPenalty;
        uint64 securityDepositValue;
        uint128 totalExpoToClose;
        uint128 lastPrice;
        uint256 tempPositionValue;
        uint256 longTradingExpo;
        HugeUint.Uint512 liqMulAcc;
    }

    /**
     * @dev Structure to hold the transient data during `_initiateOpenPosition`
     * @param adjustedPrice The adjusted price with position fees applied
     * @param posId The new position id
     * @param liquidationPenalty The liquidation penalty
     * @param positionTotalExpo The total expo of the position
     */
    struct InitiateOpenPositionData {
        uint128 adjustedPrice;
        PositionId posId;
        uint8 liquidationPenalty;
        uint128 positionTotalExpo;
    }

    function maxTick() public view returns (int24 tick_) {
        tick_ = TickMath.maxUsableTick(s._tickSpacing);
    }

    function getLongPosition(PositionId memory posId)
        public
        view
        returns (Position memory pos_, uint8 liquidationPenalty_)
    {
        (bytes32 tickHash, uint256 version) = _tickHash(posId.tick);
        if (posId.tickVersion != version) {
            revert UsdnProtocolOutdatedTick(version, posId.tickVersion);
        }
        pos_ = s._longPositions[tickHash][posId.index];
        liquidationPenalty_ = s._tickData[tickHash].liquidationPenalty;
    }

    // slither-disable-next-line write-after-write
    function getMinLiquidationPrice(uint128 price) public view returns (uint128 liquidationPrice_) {
        liquidationPrice_ = _getLiquidationPrice(price, uint128(s._minLeverage));
        int24 tick = getEffectiveTickForPrice(liquidationPrice_);
        liquidationPrice_ = getEffectivePriceForTick(tick + s._tickSpacing);
    }

    function getPositionValue(PositionId calldata posId, uint128 price, uint128 timestamp)
        external
        view
        returns (int256 value_)
    {
        (Position memory pos, uint8 liquidationPenalty) = getLongPosition(posId);
        int256 longTradingExpo = longTradingExpoWithFunding(price, timestamp);
        if (longTradingExpo < 0) {
            // In case the long balance is equal to the total expo (or exceeds it), the trading expo will become zero
            // In this case, the liquidation price will fall to zero, and the position value will be equal to its
            // total expo (initial collateral * initial leverage).
            longTradingExpo = 0;
        }
        uint128 liqPrice = getEffectivePriceForTick(
            _calcTickWithoutPenalty(posId.tick, liquidationPenalty),
            price,
            uint256(longTradingExpo),
            s._liqMultiplierAccumulator
        );
        value_ = _positionValue(price, liqPrice, pos.totalExpo);
    }

    /**
     * @notice Calculate a fixed-precision representation of the liquidation price multiplier
     * @param assetPrice The current price of the asset
     * @param longTradingExpo The trading expo of the long side (total expo - balance long)
     * @param accumulator The liquidation multiplier accumulator
     * @return multiplier_ The liquidation price multiplier, with LIQUIDATION_MULTIPLIER_DECIMALS decimals
     */
    function _calcFixedPrecisionMultiplier(
        uint256 assetPrice,
        uint256 longTradingExpo,
        HugeUint.Uint512 memory accumulator
    ) internal view returns (uint256 multiplier_) {
        if (accumulator.hi == 0 && accumulator.lo == 0) {
            // no position in long, we assume a liquidation multiplier of 1.0
            return 10 ** s.LIQUIDATION_MULTIPLIER_DECIMALS;
        }
        // M = assetPrice * (totalExpo - balanceLong) / accumulator
        HugeUint.Uint512 memory numerator =
            HugeUint.mul(10 ** s.LIQUIDATION_MULTIPLIER_DECIMALS, assetPrice * longTradingExpo);
        multiplier_ = numerator.div(accumulator);
    }

    function _checkSafetyMargin(uint128 currentPrice, uint128 liquidationPrice) internal view {
        uint128 maxLiquidationPrice = (currentPrice * (s.BPS_DIVISOR - s._safetyMarginBps) / s.BPS_DIVISOR).toUint128();
        if (liquidationPrice >= maxLiquidationPrice) {
            revert UsdnProtocolLiquidationPriceSafetyMargin(liquidationPrice, maxLiquidationPrice);
        }
    }

    function longTradingExpoWithFunding(uint128 currentPrice, uint128 timestamp) public view returns (int256 expo_) {
        expo_ = s._totalExpo.toInt256().safeSub(longAssetAvailableWithFunding(currentPrice, timestamp));
    }

    function longAssetAvailableWithFunding(uint128 currentPrice, uint128 timestamp)
        public
        view
        returns (int256 available_)
    {
        if (timestamp < s._lastUpdateTimestamp) {
            revert UsdnProtocolTimestampTooOld();
        }

        int256 ema = calcEMA(s._lastFunding, timestamp - s._lastUpdateTimestamp, s._EMAPeriod, s._EMA);
        (int256 fundAsset,) = _fundingAsset(timestamp, ema);

        if (fundAsset > 0) {
            available_ = _longAssetAvailable(currentPrice).safeSub(fundAsset);
        } else {
            int256 fee = fundAsset * _toInt256(s._protocolFeeBps) / int256(s.BPS_DIVISOR);
            // fees have the same sign as fundAsset (negative here), so we need to sub them
            available_ = _longAssetAvailable(currentPrice).safeSub(fundAsset - fee);
        }
    }

    function initiateOpenPosition(
        uint128 amount,
        uint128 desiredLiqPrice,
        bytes calldata currentPriceData,
        PreviousActionsData calldata previousActionsData,
        address to
    ) external payable initializedAndNonReentrant returns (PositionId memory posId_) {
        uint256 securityDepositValue = s._securityDepositValue;
        if (msg.value < securityDepositValue) {
            revert UsdnProtocolSecurityDepositTooLow();
        }

        uint256 balanceBefore = address(this).balance;
        uint256 amountToRefund;

        (posId_, amountToRefund) = _initiateOpenPosition(msg.sender, to, amount, desiredLiqPrice, currentPriceData);

        unchecked {
            amountToRefund += _executePendingActionOrRevert(previousActionsData);
        }
        _refundExcessEther(securityDepositValue, amountToRefund, balanceBefore);
        _checkPendingFee();
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
        if (amount < s._minLongPosition) {
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
        s._balanceLong += long.amount;
        posId_ = data.posId;

        securityDepositValue_ = _createOpenPendingAction(user, to, data);

        s._asset.safeTransferFrom(user, address(this), amount);

        emit InitiatedOpenPosition(
            user, to, uint40(block.timestamp), data.positionTotalExpo, amount, data.adjustedPrice, posId_
        );
    }

    /**
     * @notice Prepare the pending action struct for an open position and add it to the queue.
     * @param user The address of the user initiating the open position.
     * @param to The address that will be the owner of the position
     * @param data The open position action data
     * @return securityDepositValue_ The security deposit value
     */
    function _createOpenPendingAction(address user, address to, InitiateOpenPositionData memory data)
        internal
        returns (uint256 securityDepositValue_)
    {
        LongPendingAction memory action = LongPendingAction({
            action: ProtocolAction.ValidateOpenPosition,
            timestamp: uint40(block.timestamp),
            user: user,
            to: to,
            securityDepositValue: s._securityDepositValue,
            tick: data.posId.tick,
            closeAmount: 0,
            closePosTotalExpo: 0,
            tickVersion: data.posId.tickVersion,
            index: data.posId.index,
            closeLiqMultiplier: 0,
            closeBoundedPositionValue: 0
        });
        securityDepositValue_ = _addPendingAction(user, _convertLongPendingAction(action));
    }

    /**
     * @notice Convert a `LongPendingAction` to a `PendingAction`
     * @param action A long pending action
     * @return pendingAction_ The converted untyped pending action
     */
    function _convertLongPendingAction(LongPendingAction memory action)
        internal
        pure
        returns (PendingAction memory pendingAction_)
    {
        assembly {
            pendingAction_ := action
        }
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
        data_.adjustedPrice = (currentPrice.price + currentPrice.price * s._positionFeeBps / s.BPS_DIVISOR).toUint128();

        uint128 neutralPrice = currentPrice.neutralPrice.toUint128();

        _applyPnlAndFundingAndLiquidate(
            neutralPrice, currentPrice.timestamp, s._liquidationIteration, false, currentPriceData
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
     * @notice The open long imbalance limit state verification. Revert
     * @dev To ensure that the protocol does not imbalance more than
     * the open limit on long side, otherwise revert
     * @param openTotalExpoValue The open position expo value
     * @param openCollatValue The open position collateral value
     */
    // TO DO : make this internal
    function _checkImbalanceLimitOpen(uint256 openTotalExpoValue, uint256 openCollatValue) public view {
        int256 openExpoImbalanceLimitBps = s._openExpoImbalanceLimitBps;

        // early return in case limit is disabled
        if (openExpoImbalanceLimitBps == 0) {
            return;
        }

        int256 currentVaultExpo = s._balanceVault.toInt256();

        // cannot be calculated if equal zero
        if (currentVaultExpo == 0) {
            revert UsdnProtocolInvalidVaultExpo();
        }

        int256 imbalanceBps = (
            ((s._totalExpo + openTotalExpoValue).toInt256().safeSub((s._balanceLong + openCollatValue).toInt256()))
                .safeSub(currentVaultExpo)
        ).safeMul(int256(s.BPS_DIVISOR)).safeDiv(currentVaultExpo);

        if (imbalanceBps >= openExpoImbalanceLimitBps) {
            revert UsdnProtocolImbalanceLimitReached(imbalanceBps);
        }
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
        if (leverage < s._minLeverage) {
            revert UsdnProtocolLeverageTooLow();
        }
        if (leverage > s._maxLeverage) {
            revert UsdnProtocolLeverageTooHigh();
        }
    }

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
        return pending.securityDepositValue;
    }

    function initiateClosePosition(
        PositionId calldata posId,
        uint128 amountToClose,
        bytes calldata currentPriceData,
        PreviousActionsData calldata previousActionsData,
        address to
    ) external payable initializedAndNonReentrant {
        uint256 securityDepositValue = s._securityDepositValue;
        if (msg.value < securityDepositValue) {
            revert UsdnProtocolSecurityDepositTooLow();
        }

        uint256 balanceBefore = address(this).balance;

        uint256 amountToRefund = _initiateClosePosition(msg.sender, to, posId, amountToClose, currentPriceData);
        unchecked {
            amountToRefund += _executePendingActionOrRevert(previousActionsData);
        }
        _refundExcessEther(securityDepositValue, amountToRefund, balanceBefore);
        _checkPendingFee();
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

        s._balanceLong -= data.tempPositionValue;

        _removeAmountFromPosition(posId.tick, posId.index, data.pos, amountToClose, data.totalExpoToClose);

        emit InitiatedClosePosition(
            user, to, posId, data.pos.amount, amountToClose, data.pos.totalExpo - data.totalExpoToClose
        );
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
            action: ProtocolAction.ValidateClosePosition,
            timestamp: uint40(block.timestamp),
            user: user,
            to: to,
            securityDepositValue: data.securityDepositValue,
            tick: posId.tick,
            closeAmount: amountToClose,
            closePosTotalExpo: data.totalExpoToClose,
            tickVersion: posId.tickVersion,
            index: posId.index,
            closeLiqMultiplier: _calcFixedPrecisionMultiplier(data.lastPrice, data.longTradingExpo, data.liqMulAcc),
            closeBoundedPositionValue: data.tempPositionValue
        });
        securityDepositValue_ = _addPendingAction(user, _convertLongPendingAction(action));
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

        _applyPnlAndFundingAndLiquidate(
            currentPrice.neutralPrice, currentPrice.timestamp, s._liquidationIteration, false, currentPriceData
        );

        (, uint256 version) = _tickHash(posId.tick);
        if (version != posId.tickVersion) {
            // The current tick version doesn't match the version from the position,
            // that means that the position has been liquidated in this transaction.
            return (data_, true);
        }

        data_.totalExpoToClose = (uint256(data_.pos.totalExpo) * amountToClose / data_.pos.amount).toUint128();

        _checkImbalanceLimitClose(data_.totalExpoToClose, amountToClose);

        data_.longTradingExpo = s._totalExpo - s._balanceLong;
        data_.liqMulAcc = s._liqMultiplierAccumulator;
        data_.lastPrice = s._lastPrice;

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

        data_.securityDepositValue = s._securityDepositValue;
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
        uint256 available = s._balanceLong;

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
     * @notice The close vault imbalance limit state verification
     * @dev To ensure that the protocol does not imbalance more than
     * the close limit on vault side, otherwise revert
     * @param closePosTotalExpoValue The close position total expo value
     * @param closeCollatValue The close position collateral value
     */
    function _checkImbalanceLimitClose(uint256 closePosTotalExpoValue, uint256 closeCollatValue) internal view {
        int256 closeExpoImbalanceLimitBps = s._closeExpoImbalanceLimitBps;

        // early return in case limit is disabled
        if (closeExpoImbalanceLimitBps == 0) {
            return;
        }

        int256 newLongExpo = (s._totalExpo.toInt256().safeSub(closePosTotalExpoValue.toInt256())).safeSub(
            s._balanceLong.toInt256().safeSub(closeCollatValue.toInt256())
        );

        // cannot be calculated if equal or lower than zero
        if (newLongExpo <= 0) {
            revert UsdnProtocolInvalidLongExpo();
        }

        int256 imbalanceBps =
            (s._balanceVault.toInt256().safeSub(newLongExpo)).safeMul(int256(s.BPS_DIVISOR)).safeDiv(newLongExpo);

        if (imbalanceBps >= closeExpoImbalanceLimitBps) {
            revert UsdnProtocolImbalanceLimitReached(imbalanceBps);
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
        if (remainingAmount > 0 && remainingAmount < s._minLongPosition) {
            revert UsdnProtocolLongPositionTooSmall();
        }

        if (amountToClose == 0) {
            revert UsdnProtocolAmountToCloseIsZero();
        }

        if (to == address(0)) {
            revert UsdnProtocolInvalidAddressTo();
        }
    }

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
        return pending.securityDepositValue;
    }
}

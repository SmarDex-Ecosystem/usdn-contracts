// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { FixedPointMathLib } from "solady/src/utils/FixedPointMathLib.sol";

import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { LibBitmap } from "solady/src/utils/LibBitmap.sol";
import { PriceInfo } from "src/interfaces/OracleMiddleware/IOracleMiddlewareTypes.sol";
import { TickMath } from "src/libraries/TickMath.sol";

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
import { UsdnProtocolBaseStorage } from "src/UsdnProtocol/UsdnProtocolBaseStorage.sol";
import { IUsdn } from "src/interfaces/Usdn/IUsdn.sol";
import { SignedMath } from "src/libraries/SignedMath.sol";
import { HugeUint } from "src/libraries/HugeUint.sol";
import { IUsdnProtocolEvents } from "src/interfaces/UsdnProtocol/IUsdnProtocolEvents.sol";
import { DoubleEndedQueue } from "src/libraries/DoubleEndedQueue.sol";
import { IUsdnProtocolCommon } from "src/interfaces/UsdnProtocol/IUsdnProtocolCommon.sol";

abstract contract UsdnProtocolCommon is UsdnProtocolBaseStorage, IUsdnProtocolCommon, IUsdnProtocolEvents {
    using SafeERC20 for IERC20Metadata;
    using SafeERC20 for IUsdn;
    using SafeCast for uint256;
    using SafeCast for int256;
    using LibBitmap for LibBitmap.Bitmap;
    using SignedMath for int256;
    using HugeUint for HugeUint.Uint512;
    using DoubleEndedQueue for DoubleEndedQueue.Deque;

    /**
     * @notice Structure to hold the temporary data during liquidation
     * @param tempLongBalance The temporary long balance
     * @param tempVaultBalance The temporary vault balance
     * @param currentTick The current tick (tick corresponding to the current asset price)
     * @param iTick Tick iterator index
     * @param totalExpoToRemove The total expo to remove due to the liquidation of some ticks
     * @param accumulatorValueToRemove The value to remove from the liquidation multiplier accumulator, due to the
     * liquidation of some ticks
     * @param longTradingExpo The long trading expo
     * @param currentPrice The current price of the asset
     * @param accumulator The liquidation multiplier accumulator before the liquidation
     */
    struct LiquidationData {
        int256 tempLongBalance;
        int256 tempVaultBalance;
        int24 currentTick;
        int24 iTick;
        uint256 totalExpoToRemove;
        uint256 accumulatorValueToRemove;
        uint256 longTradingExpo;
        uint256 currentPrice;
        HugeUint.Uint512 accumulator;
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
     */
    struct ValidateOpenPositionData {
        LongPendingAction action;
        uint128 startPrice;
        bytes32 tickHash;
        Position pos;
        uint128 liqPriceWithoutPenalty;
        uint128 leverage;
        uint8 liquidationPenalty;
    }

    /**
     * @notice Convert a uint128 to an int256
     * @param x The value to convert
     * @return The converted value
     */
    function _toInt256(uint128 x) internal pure returns (int256) {
        return int256(uint256(x));
    }

    /**
     * @notice Get the predicted value of the funding (in asset units) since the last state update for the given
     * timestamp
     * @dev If the provided timestamp is older than the last state update, the result will be zero
     * @param timestamp The current timestamp
     * @param ema The EMA of the funding rate
     * @return fundingAsset_ The number of asset tokens of funding (with asset decimals)
     * @return fund_ The magnitude of the funding (with `FUNDING_RATE_DECIMALS` decimals)
     */
    function _fundingAsset(uint128 timestamp, int256 ema) internal view returns (int256 fundingAsset_, int256 fund_) {
        int256 oldLongExpo;
        (fund_, oldLongExpo) = _funding(timestamp, ema);
        fundingAsset_ = fund_.safeMul(oldLongExpo) / int256(10) ** s.FUNDING_RATE_DECIMALS;
    }

    /**
     * @notice Calculate the funding rate and the old long exposure
     * @param timestamp The current timestamp
     * @param ema The EMA of the funding rate
     * @return fund_ The funding rate
     * @return oldLongExpo_ The old long exposure
     */
    function _funding(uint128 timestamp, int256 ema) internal view returns (int256 fund_, int256 oldLongExpo_) {
        oldLongExpo_ = s._totalExpo.toInt256().safeSub(s._balanceLong.toInt256());

        if (timestamp < s._lastUpdateTimestamp) {
            revert UsdnProtocolTimestampTooOld();
            // slither-disable-next-line incorrect-equality
        } else if (timestamp == s._lastUpdateTimestamp) {
            return (0, oldLongExpo_);
        }

        int256 oldVaultExpo = s._balanceVault.toInt256();

        // ImbalanceIndex = (longExpo - vaultExpo) / max(longExpo, vaultExpo)
        // fund = (sign(ImbalanceIndex) * ImbalanceIndex^2 * fundingSF) + _EMA
        // fund = (sign(ImbalanceIndex) * (longExpo - vaultExpo)^2 * fundingSF / denominator) + _EMA
        // with denominator = vaultExpo^2 if vaultExpo > longExpo, or longExpo^2 if longExpo > vaultExpo

        int256 numerator = oldLongExpo_ - oldVaultExpo;
        // optimization: if the numerator is zero, then return the EMA
        // slither-disable-next-line incorrect-equality
        if (numerator == 0) {
            return (ema, oldLongExpo_);
        }

        if (oldLongExpo_ <= 0) {
            // if oldLongExpo is negative, then we cap the imbalance index to -1
            // oldVaultExpo is always positive
            return (-int256(s._fundingSF * 10 ** (s.FUNDING_RATE_DECIMALS - s.FUNDING_SF_DECIMALS)) + ema, oldLongExpo_);
        } else if (oldVaultExpo == 0) {
            // if oldVaultExpo is zero (can't be negative), then we cap the imbalance index to 1
            // oldLongExpo must be positive in this case
            return (int256(s._fundingSF * 10 ** (s.FUNDING_RATE_DECIMALS - s.FUNDING_SF_DECIMALS)) + ema, oldLongExpo_);
        }

        // starting here, oldLongExpo and oldVaultExpo are always strictly positive

        uint256 elapsedSeconds = timestamp - s._lastUpdateTimestamp;
        uint256 numerator_squared = uint256(numerator * numerator);

        uint256 denominator;
        if (oldVaultExpo > oldLongExpo_) {
            // we have to multiply by 1 day to get the correct units
            denominator = uint256(oldVaultExpo * oldVaultExpo) * 1 days;
            fund_ = -int256(
                FixedPointMathLib.fullMulDiv(
                    numerator_squared * elapsedSeconds,
                    s._fundingSF * 10 ** (s.FUNDING_RATE_DECIMALS - s.FUNDING_SF_DECIMALS),
                    denominator
                )
            ) + ema;
        } else {
            // we have to multiply by 1 day to get the correct units
            denominator = uint256(oldLongExpo_ * oldLongExpo_) * 1 days;
            fund_ = int256(
                FixedPointMathLib.fullMulDiv(
                    numerator_squared * elapsedSeconds,
                    s._fundingSF * 10 ** (s.FUNDING_RATE_DECIMALS - s.FUNDING_SF_DECIMALS),
                    denominator
                )
            ) + ema;
        }
    }

    function calcEMA(int256 lastFunding, uint128 secondsElapsed, uint128 emaPeriod, int256 previousEMA)
        public
        pure
        returns (int256)
    {
        if (secondsElapsed >= emaPeriod) {
            return lastFunding;
        }

        return (lastFunding + previousEMA * _toInt256(emaPeriod - secondsElapsed)) / _toInt256(emaPeriod);
    }

    /**
     * @notice Function to calculate the hash and version of a given tick
     * @param tick The tick
     * @return hash_ The hash of the tick
     * @return version_ The version of the tick
     */
    function _tickHash(int24 tick) public view returns (bytes32 hash_, uint256 version_) {
        version_ = s._tickVersion[tick];
        hash_ = tickHash(tick, version_);
    }

    /**
     * @notice Calculate the PnL in asset units of the long side, considering the overall total expo and change in
     * price
     * @param totalExpo The total exposure of the long side
     * @param balanceLong The (old) balance of the long side
     * @param newPrice The new price
     * @param oldPrice The old price when the old balance was updated
     * @return pnl_ The PnL in asset units
     */
    function _pnlAsset(uint256 totalExpo, uint256 balanceLong, uint128 newPrice, uint128 oldPrice)
        internal
        pure
        returns (int256 pnl_)
    {
        // in case of a negative trading expo, we can't allow calculation of PnL because it would invert the sign of the
        // calculated amount. We thus disable any balance update due to PnL in such a case
        if (balanceLong >= totalExpo) {
            return 0;
        }
        int256 priceDiff = _toInt256(newPrice) - _toInt256(oldPrice);
        pnl_ = totalExpo.toInt256().safeSub(balanceLong.toInt256()).safeMul(priceDiff).safeDiv(_toInt256(newPrice));
    }

    /**
     * @notice Calculate the long balance taking into account unreflected PnL (but not funding)
     * @dev This function uses the latest total expo, balance and stored price as the reference values, and adds the PnL
     * due to the price change to `currentPrice`
     * @param currentPrice The current price
     * @return available_ The available balance on the long side
     */
    function _longAssetAvailable(uint128 currentPrice) public view returns (int256 available_) {
        available_ = _longAssetAvailable(s._totalExpo, s._balanceLong, currentPrice, s._lastPrice);
    }

    /**
     * @notice Calculate the long balance taking into account unreflected PnL (but not funding)
     * @param totalExpo The total exposure of the long side
     * @param balanceLong The (old) balance of the long side
     * @param newPrice The new price
     * @param oldPrice The old price when the old balance was updated
     * @return available_ The available balance on the long side
     */
    function _longAssetAvailable(uint256 totalExpo, uint256 balanceLong, uint128 newPrice, uint128 oldPrice)
        internal
        pure
        returns (int256 available_)
    {
        // Avoid division by zero
        // slither-disable-next-line incorrect-equality
        if (totalExpo == 0) {
            return 0;
        }

        available_ = balanceLong.toInt256().safeAdd(_pnlAsset(totalExpo, balanceLong, newPrice, oldPrice));
    }

    /**
     * @notice Refunds any excess ether to the user to prevent locking ETH in the contract.
     * @param securityDepositValue The security deposit value of the action (zero for a validation action).
     * @param amountToRefund The amount to refund to the user:
     *      - the security deposit if executing an action for another user,
     *      - the initialization security deposit in case of a validation action.
     * @param balanceBefore The balance of the contract before the action.
     */
    function _refundExcessEther(uint256 securityDepositValue, uint256 amountToRefund, uint256 balanceBefore)
        public
        payable
    {
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
        if (s._pendingProtocolFee >= s._feeThreshold) {
            s._asset.safeTransfer(s._feeCollector, s._pendingProtocolFee);
            emit ProtocolFeeDistributed(s._feeCollector, s._pendingProtocolFee);
            s._pendingProtocolFee = 0;
        }
    }

    /**
     * @notice Execute the first actionable pending action or revert if the price data was not provided.
     * @param data The price data and raw indices
     * @return securityDepositValue_ The security deposit value of the executed action
     */
    function _executePendingActionOrRevert(PreviousActionsData calldata data)
        public
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
        public
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
        securityDepositValue_ = pending.securityDepositValue;
        emit SecurityDepositRefunded(pending.user, msg.sender, securityDepositValue_);
    }

    function _validateClosePositionWithAction(PendingAction memory pending, bytes calldata priceData) internal {
        LongPendingAction memory long = _toLongPendingAction(pending);

        PriceInfo memory currentPrice = _getOraclePrice(ProtocolAction.ValidateClosePosition, long.timestamp, priceData);

        _applyPnlAndFundingAndLiquidate(
            currentPrice.neutralPrice, currentPrice.timestamp, s._liquidationIteration, false, priceData
        );

        // Apply fees on price
        uint128 priceWithFees =
            (currentPrice.price - currentPrice.price * s._positionFeeBps / s.BPS_DIVISOR).toUint128();

        // get liquidation price (with liq penalty) to check if position was valid at `timestamp + validationDelay`
        uint128 liquidationPrice = _getEffectivePriceForTick(long.tick, long.closeLiqMultiplier);

        if (currentPrice.neutralPrice <= liquidationPrice) {
            // Position should be liquidated, we don't transfer assets to the user.
            // Position was already removed from tick so no additional bookkeeping is necessary.
            // Credit the full amount to the vault to preserve the total balance invariant.
            s._balanceVault += long.closeBoundedPositionValue;
            emit LiquidatedPosition(
                long.user,
                PositionId({ tick: long.tick, tickVersion: long.tickVersion, index: long.index }),
                currentPrice.neutralPrice,
                liquidationPrice
            );
            return;
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
                s._balanceVault += remainingCollateral;
            } else if (assetToTransfer > long.closeBoundedPositionValue) {
                uint256 missingValue;
                unchecked {
                    // since assetToTransfer is strictly larger than closeBoundedPositionValue, this operation can't
                    // underflow
                    missingValue = assetToTransfer - long.closeBoundedPositionValue;
                }
                uint256 balanceVault = s._balanceVault;
                // If the vault does not have enough balance left to pay out the missing value, we take what we can
                if (missingValue > balanceVault) {
                    s._balanceVault = 0;
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
                        s._balanceVault = balanceVault - missingValue;
                    }
                }
            }
        }
        // in case the position value is zero or negative, we don't transfer any asset to the user

        // send the asset to the user
        if (assetToTransfer > 0) {
            s._asset.safeTransfer(long.to, assetToTransfer);
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
     * @notice Variant of `getEffectivePriceForTick` when a fixed precision representation of the liquidation
     * multiplier
     * is known
     * @param tick The tick number
     * @param liqMultiplier The liquidation price multiplier, with LIQUIDATION_MULTIPLIER_DECIMALS decimals
     * @return price_ The adjusted price for the tick
     */
    function _getEffectivePriceForTick(int24 tick, uint256 liqMultiplier) public view returns (uint128 price_) {
        price_ = _adjustPrice(TickMath.getPriceAtTick(tick), liqMultiplier);
    }

    /**
     * @notice Variant of _adjustPrice when a fixed precision representation of the liquidation multiplier is known
     * @param unadjustedPrice The unadjusted price for the tick
     * @param liqMultiplier The liquidation price multiplier, with LIQUIDATION_MULTIPLIER_DECIMALS decimals
     * @return price_ The adjusted price for the tick
     */
    function _adjustPrice(uint256 unadjustedPrice, uint256 liqMultiplier) public view returns (uint128 price_) {
        // price = unadjustedPrice * M
        price_ = FixedPointMathLib.fullMulDiv(unadjustedPrice, liqMultiplier, 10 ** s.LIQUIDATION_MULTIPLIER_DECIMALS)
            .toUint128();
    }

    /**
     * @notice Calculate the value of a position, knowing its liquidation price and the current asset price
     * @param currentPrice The current price of the asset
     * @param liqPriceWithoutPenalty The liquidation price of the position without the liquidation penalty
     * @param positionTotalExpo The total expo of the position
     * @return value_ The value of the position. If the current price is smaller than the liquidation price without
     * penalty, then the position value is negative (bad debt)
     */
    function _positionValue(uint128 currentPrice, uint128 liqPriceWithoutPenalty, uint128 positionTotalExpo)
        public
        pure
        returns (int256 value_)
    {
        if (currentPrice < liqPriceWithoutPenalty) {
            value_ = -FixedPointMathLib.fullMulDiv(positionTotalExpo, liqPriceWithoutPenalty - currentPrice, currentPrice)
                .toInt256();
        } else {
            value_ = FixedPointMathLib.fullMulDiv(
                positionTotalExpo, currentPrice - liqPriceWithoutPenalty, currentPrice
            ).toInt256();
        }
    }

    /**
     * @notice Validate an open position action.
     * @param pending The pending action data
     * @param priceData The current price data
     */
    function _validateOpenPositionWithAction(PendingAction memory pending, bytes calldata priceData) internal {
        (ValidateOpenPositionData memory data, bool liquidated) = _prepareValidateOpenPositionData(pending, priceData);
        if (liquidated) {
            return;
        }

        // Leverage is always greater than 1 (liquidationPrice is positive).
        // Even if it drops below _minLeverage between the initiate and validate actions, we still allow it.
        // However, if the leverage exceeds max leverage, then we adjust the liquidation price (tick) to have a leverage
        // of _maxLeverage
        uint128 maxLeverage = uint128(s._maxLeverage);
        if (data.leverage > maxLeverage) {
            // theoretical liquidation price for _maxLeverage
            data.liqPriceWithoutPenalty = _getLiquidationPrice(data.startPrice, maxLeverage);
            // adjust to closest valid tick down
            int24 tickWithoutPenalty = getEffectiveTickForPrice(data.liqPriceWithoutPenalty);

            // apply liquidation penalty with the current penalty setting
            uint8 currentLiqPenalty = s._liquidationPenalty;
            PositionId memory newPosId;
            newPosId.tick = tickWithoutPenalty + int24(uint24(currentLiqPenalty)) * s._tickSpacing;
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
            return;
        }

        // Calculate the new total expo
        uint128 expoBefore = data.pos.totalExpo;
        uint128 expoAfter = _calculatePositionTotalExpo(data.pos.amount, data.startPrice, data.liqPriceWithoutPenalty);

        // Update the total expo of the position
        s._longPositions[data.tickHash][data.action.index].totalExpo = expoAfter;
        // Update the total expo by adding the position's new expo and removing the old one.
        // Do not use += or it will underflow
        s._totalExpo = s._totalExpo + expoAfter - expoBefore;

        // update the tick data and the liqMultiplierAccumulator
        {
            TickData storage tickData = s._tickData[data.tickHash];
            uint256 unadjustedTickPrice =
                TickMath.getPriceAtTick(data.action.tick - int24(uint24(data.liquidationPenalty)) * s._tickSpacing);
            tickData.totalExpo = tickData.totalExpo + expoAfter - expoBefore;
            s._liqMultiplierAccumulator = s._liqMultiplierAccumulator.add(
                HugeUint.wrap(expoAfter * unadjustedTickPrice)
            ).sub(HugeUint.wrap(expoBefore * unadjustedTickPrice));
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
     * @notice Calculate the theoretical liquidation price of a position knowing its start price and leverage
     * @param startPrice Entry price of the position
     * @param leverage Leverage of the position
     */
    function _getLiquidationPrice(uint128 startPrice, uint128 leverage) public view returns (uint128 price_) {
        price_ = (startPrice - ((uint256(10) ** s.LEVERAGE_DECIMALS * startPrice) / leverage)).toUint128();
    }

    function getEffectiveTickForPrice(uint128 price) public payable returns (int24 tick_) {
        tick_ = getEffectiveTickForPrice(
            price, s._lastPrice, s._totalExpo - s._balanceLong, s._liqMultiplierAccumulator, s._tickSpacing
        );
    }

    function getEffectiveTickForPrice(
        uint128 price,
        uint256 assetPrice,
        uint256 longTradingExpo,
        HugeUint.Uint512 memory accumulator,
        int24 tickSpacing
    ) public pure returns (int24 tick_) {
        // unadjust price with liquidation multiplier
        uint256 unadjustedPrice = _unadjustPrice(price, assetPrice, longTradingExpo, accumulator);

        if (unadjustedPrice < TickMath.MIN_PRICE) {
            return TickMath.minUsableTick(tickSpacing);
        }

        tick_ = TickMath.getTickAtPrice(unadjustedPrice);

        // round down to the next valid tick according to _tickSpacing (towards negative infinity)
        if (tick_ < 0) {
            // we round up the inverse number (positive) then invert it -> round towards negative infinity
            tick_ = -int24(int256(FixedPointMathLib.divUp(uint256(int256(-tick_)), uint256(int256(tickSpacing)))))
                * tickSpacing;
            // avoid invalid ticks
            int24 minUsableTick = TickMath.minUsableTick(tickSpacing);
            if (tick_ < minUsableTick) {
                tick_ = minUsableTick;
            }
        } else {
            // rounding is desirable here
            // slither-disable-next-line divide-before-multiply
            tick_ = (tick_ / tickSpacing) * tickSpacing;
        }
    }

    /**
     * @notice Remove the provided total amount from its position and update the tick data and position
     * @dev Note: this method does not update the long balance
     * If the amount to remove is greater than or equal to the position's total amount, the position is deleted
     * instead
     * @param tick The tick to remove from
     * @param index Index of the position in the tick array
     * @param pos The position to remove the amount from
     * @param amountToRemove The amount to remove from the position
     * @param totalExpoToRemove The total expo to remove from the position
     */
    function _removeAmountFromPosition(
        int24 tick,
        uint256 index,
        Position memory pos,
        uint128 amountToRemove,
        uint128 totalExpoToRemove
    ) public {
        (bytes32 tickHash,) = _tickHash(tick);
        TickData storage tickData = s._tickData[tickHash];
        uint256 unadjustedTickPrice =
            TickMath.getPriceAtTick(tick - int24(uint24(tickData.liquidationPenalty)) * s._tickSpacing);
        if (amountToRemove < pos.amount) {
            Position storage position = s._longPositions[tickHash][index];
            position.totalExpo = pos.totalExpo - totalExpoToRemove;

            unchecked {
                position.amount = pos.amount - amountToRemove;
            }
        } else {
            totalExpoToRemove = pos.totalExpo;
            tickData.totalPos -= 1;
            --s._totalLongPositions;

            // Remove from tick array (set to zero to avoid shifting indices)
            delete s._longPositions[tickHash][index];
            if (tickData.totalPos == 0) {
                // we removed the last position in the tick
                s._tickBitmap.unset(_calcBitmapIndexFromTick(tick));
            }
        }

        s._totalExpo -= totalExpoToRemove;
        tickData.totalExpo -= totalExpoToRemove;
        s._liqMultiplierAccumulator =
            s._liqMultiplierAccumulator.sub(HugeUint.wrap(unadjustedTickPrice * totalExpoToRemove));
    }

    function getTickLiquidationPenalty(int24 tick) public view returns (uint8 liquidationPenalty_) {
        (bytes32 tickHash,) = _tickHash(tick);
        liquidationPenalty_ = _getTickLiquidationPenalty(tickHash);
    }

    /**
     * @notice Retrieve the liquidation penalty assigned to the tick and version corresponding to `tickHash`, if
     * there
     * are positions in it, otherwise retrieve the current setting value from storage.
     * @dev This method allows to re-use a pre-computed tickHash if available
     * @param tickHash The tick hash
     * @return liquidationPenalty_ The liquidation penalty, in tick spacing units
     */
    function _getTickLiquidationPenalty(bytes32 tickHash) internal view returns (uint8 liquidationPenalty_) {
        TickData storage tickData = s._tickData[tickHash];
        liquidationPenalty_ = tickData.totalPos != 0 ? tickData.liquidationPenalty : s._liquidationPenalty;
    }

    /**
     * @notice Save a new position in the protocol, adjusting the tick data and global variables
     * @dev Note: this method does not update the long balance
     * @param tick The tick to hold the new position
     * @param long The position to save
     * @param liquidationPenalty The liquidation penalty for the tick
     */
    function _saveNewPosition(int24 tick, Position memory long, uint8 liquidationPenalty)
        public
        payable
        returns (uint256 tickVersion_, uint256 index_)
    {
        bytes32 tickHash;
        (tickHash, tickVersion_) = _tickHash(tick);

        // Add to tick array
        Position[] storage tickArray = s._longPositions[tickHash];
        index_ = tickArray.length;
        if (tick > s._highestPopulatedTick) {
            // keep track of the highest populated tick
            s._highestPopulatedTick = tick;
        }
        tickArray.push(long);

        // Adjust state
        s._totalExpo += long.totalExpo;
        ++s._totalLongPositions;

        // Update tick data
        TickData storage tickData = s._tickData[tickHash];
        // The unadjusted tick price for the accumulator might be different depending if we already have positions in
        // the tick or not
        uint256 unadjustedTickPrice;
        if (tickData.totalPos == 0) {
            // first position in this tick, we need to reflect that it is populated
            s._tickBitmap.set(_calcBitmapIndexFromTick(tick));
            // we store the data for this tick
            tickData.totalExpo = long.totalExpo;
            tickData.totalPos = 1;
            tickData.liquidationPenalty = liquidationPenalty;
            unadjustedTickPrice = TickMath.getPriceAtTick(tick - int24(uint24(liquidationPenalty)) * s._tickSpacing);
        } else {
            tickData.totalExpo += long.totalExpo;
            tickData.totalPos += 1;
            // we do not need to adjust the tick's liquidationPenalty since it remains constant
            unadjustedTickPrice =
                TickMath.getPriceAtTick(tick - int24(uint24(tickData.liquidationPenalty)) * s._tickSpacing);
        }
        // Update the accumulator with the correct tick price (depending on the liquidation penalty value)
        s._liqMultiplierAccumulator =
            s._liqMultiplierAccumulator.add(HugeUint.wrap(unadjustedTickPrice * long.totalExpo));
    }

    /**
     * @notice Calculate the total exposure of a position
     * @dev Reverts when startPrice <= liquidationPrice
     * @param amount The amount of asset used as collateral
     * @param startPrice The price of the asset when the position was created
     * @param liquidationPrice The liquidation price of the position
     * @return totalExpo_ The total exposure of a position
     */
    function _calculatePositionTotalExpo(uint128 amount, uint128 startPrice, uint128 liquidationPrice)
        public
        payable
        returns (uint128 totalExpo_)
    {
        if (startPrice <= liquidationPrice) {
            revert UsdnProtocolInvalidLiquidationPrice(liquidationPrice, startPrice);
        }

        totalExpo_ = FixedPointMathLib.fullMulDiv(amount, startPrice, startPrice - liquidationPrice).toUint128();
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
        data_.startPrice = (currentPrice.price + currentPrice.price * s._positionFeeBps / s.BPS_DIVISOR).toUint128();

        _applyPnlAndFundingAndLiquidate(
            currentPrice.neutralPrice, currentPrice.timestamp, s._liquidationIteration, false, priceData
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
        data_.pos = s._longPositions[data_.tickHash][data_.action.index];
        // Re-calculate leverage
        data_.liquidationPenalty = s._tickData[data_.tickHash].liquidationPenalty;
        data_.liqPriceWithoutPenalty =
            getEffectivePriceForTick(_calcTickWithoutPenalty(data_.action.tick, data_.liquidationPenalty));
        // reverts if liqPriceWithoutPenalty >= startPrice
        data_.leverage = _getLeverage(data_.startPrice, data_.liqPriceWithoutPenalty);
    }

    function getEffectivePriceForTick(int24 tick) public payable returns (uint128 price_) {
        price_ =
            getEffectivePriceForTick(tick, s._lastPrice, s._totalExpo - s._balanceLong, s._liqMultiplierAccumulator);
    }

    /// @dev This does not take into account the liquidation penalty
    function _getLeverage(uint128 startPrice, uint128 liquidationPrice) public view returns (uint128 leverage_) {
        if (startPrice <= liquidationPrice) {
            // this situation is not allowed (newly open position must be solvent)
            // Also, calculation below would underflow
            revert UsdnProtocolInvalidLiquidationPrice(liquidationPrice, startPrice);
        }

        leverage_ = ((10 ** s.LEVERAGE_DECIMALS * uint256(startPrice)) / (startPrice - liquidationPrice)).toUint128();
    }

    function _validateWithdrawalWithAction(PendingAction memory pending, bytes calldata priceData) internal {
        WithdrawalPendingAction memory withdrawal = _toWithdrawalPendingAction(pending);

        PriceInfo memory currentPrice =
            _getOraclePrice(ProtocolAction.ValidateWithdrawal, withdrawal.timestamp, priceData);

        _applyPnlAndFundingAndLiquidate(
            currentPrice.neutralPrice, currentPrice.timestamp, s._liquidationIteration, false, priceData
        );

        // Apply fees on price
        uint128 withdrawalPriceWithFees =
            (currentPrice.price + currentPrice.price * s._vaultFeeBps / s.BPS_DIVISOR).toUint128();

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
        IUsdn usdn = s._usdn;

        uint256 assetToTransfer = _calcBurnUsdn(shares, available, usdn.totalShares());

        usdn.burnShares(shares);

        // send the asset to the user
        if (assetToTransfer > 0) {
            s._balanceVault -= assetToTransfer;
            s._asset.safeTransfer(withdrawal.to, assetToTransfer);
        }

        emit ValidatedWithdrawal(
            withdrawal.user, withdrawal.to, assetToTransfer, usdn.convertToTokens(shares), withdrawal.timestamp
        );
    }

    /**
     * @notice Merge the two parts of the withdrawal amount (USDN shares) stored in the `WithdrawalPendingAction`.
     * @param sharesLSB The lower 24 bits of the USDN shares
     * @param sharesMSB The higher bits of the USDN shares
     * @return usdnShares_ The amount of USDN shares
     */
    function _mergeWithdrawalAmountParts(uint24 sharesLSB, uint128 sharesMSB)
        public
        pure
        returns (uint256 usdnShares_)
    {
        usdnShares_ = sharesLSB | uint256(sharesMSB) << 24;
    }

    /**
     * @notice Calculate the amount of assets received when burning USDN shares
     * @param usdnShares The amount of USDN shares
     * @param available The available asset in the vault
     * @param usdnTotalShares The total supply of USDN shares
     * @return assetExpected_ The expected amount of asset to be received
     */
    function _calcBurnUsdn(uint256 usdnShares, uint256 available, uint256 usdnTotalShares)
        public
        pure
        returns (uint256 assetExpected_)
    {
        // assetExpected = amountUsdn * usdnPrice / assetPrice = amountUsdn * assetAvailable / totalSupply
        //                 = shares * assetAvailable / usdnTotalShares
        assetExpected_ = FixedPointMathLib.fullMulDiv(usdnShares, available, usdnTotalShares);
    }

    function _validateDepositWithAction(PendingAction memory pending, bytes calldata priceData) internal {
        DepositPendingAction memory deposit = _toDepositPendingAction(pending);

        PriceInfo memory currentPrice = _getOraclePrice(ProtocolAction.ValidateDeposit, deposit.timestamp, priceData);

        // adjust balances
        _applyPnlAndFundingAndLiquidate(
            currentPrice.neutralPrice, currentPrice.timestamp, s._liquidationIteration, false, priceData
        );

        // We calculate the amount of USDN to mint, either considering the asset price at the time of the initiate
        // action, or the current price provided for validation. We will use the lower of the two amounts to mint.
        // Apply fees on price
        uint128 priceWithFees = (currentPrice.price - currentPrice.price * s._vaultFeeBps / s.BPS_DIVISOR).toUint128();

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

        s._balanceVault += deposit.amount;

        s._usdn.mint(deposit.to, usdnToMint);
        emit ValidatedDeposit(deposit.user, deposit.to, deposit.amount, usdnToMint, deposit.timestamp);
    }

    /**
     * @notice Calculates the amount of USDN to mint for a given amount of asset
     * @param amount The amount of asset to be converted into USDN
     * @param vaultBalance The balance of the vault (not used for initialization)
     * @param usdnTotalSupply The total supply of USDN (not used for initialization)
     * @param price The price of the asset (only used for initialization)
     * @return toMint_ The amount of USDN to mint
     * @dev The amount of USDN to mint is calculated as follows:
     * amountUsdn = amountAsset * priceAsset / priceUsdn,
     * but since priceUsdn = vaultBalance * priceAsset / totalSupply, we can simplify to
     * amountUsdn = amountAsset * totalSupply / vaultBalance.
     */
    function _calcMintUsdn(uint256 amount, uint256 vaultBalance, uint256 usdnTotalSupply, uint256 price)
        public
        payable
        returns (uint256 toMint_)
    {
        if (vaultBalance == 0) {
            // initialization, we consider the USDN price to be 1 USD
            return FixedPointMathLib.fullMulDiv(
                amount, price, 10 ** (s._assetDecimals + s._priceFeedDecimals - s.TOKENS_DECIMALS)
            );
        }
        toMint_ = FixedPointMathLib.fullMulDiv(amount, usdnTotalSupply, vaultBalance);
    }

    /**
     * @notice Available balance in the vault side if the price moves to `currentPrice` (without taking funding into
     * account)
     * @param totalExpo The total expo
     * @param balanceVault The (old) balance of the vault
     * @param balanceLong The (old) balance of the long side
     * @param newPrice The new price
     * @param oldPrice The old price when the old balances were updated
     * @return available_ The available balance in the vault side
     */
    function _vaultAssetAvailable(
        uint256 totalExpo,
        uint256 balanceVault,
        uint256 balanceLong,
        uint128 newPrice,
        uint128 oldPrice
    ) public pure returns (int256 available_) {
        int256 totalBalance = balanceLong.toInt256().safeAdd(balanceVault.toInt256());
        int256 newLongBalance = _longAssetAvailable(totalExpo, balanceLong, newPrice, oldPrice);

        available_ = totalBalance.safeSub(newLongBalance);
    }

    /**
     * @notice This is the mutating version of `getActionablePendingAction`, where empty items at the front of the list
     * are removed
     * @return action_ The first actionable pending action if any, otherwise a struct with all fields set to zero and
     * ProtocolAction.None
     * @return rawIndex_ The raw index in the queue for the returned pending action, or zero
     */
    function _getActionablePendingAction() public returns (PendingAction memory action_, uint128 rawIndex_) {
        uint256 queueLength = s._pendingActionsQueue.length();
        if (queueLength == 0) {
            // empty queue, early return
            return (action_, rawIndex_);
        }
        uint256 maxIter = s.MAX_ACTIONABLE_PENDING_ACTIONS;
        if (queueLength < maxIter) {
            maxIter = queueLength;
        }

        uint256 i = 0;
        do {
            // since we will never call `front` more than `queueLength` times, there is no risk of reverting
            (PendingAction memory candidate, uint128 rawIndex) = s._pendingActionsQueue.front();
            // gas optimization
            unchecked {
                i++;
            }
            if (candidate.timestamp == 0) {
                // remove the stale pending action
                // slither-disable-next-line unused-return
                s._pendingActionsQueue.popFront();
                // try the next one
                continue;
            } else if (candidate.timestamp + s._validationDeadline < block.timestamp) {
                // we found an actionable pending action
                return (candidate, rawIndex);
            }
            // the first pending action is not actionable
            return (action_, rawIndex_);
        } while (i < maxIter);
    }

    /**
     * @notice Clear the pending action for a user
     * @param user The user's address
     */
    function _clearPendingAction(address user) internal {
        uint256 pendingActionIndex = s._pendingActions[user];
        // slither-disable-next-line incorrect-equality
        if (pendingActionIndex == 0) {
            revert UsdnProtocolNoPendingAction();
        }
        uint128 rawIndex = uint128(pendingActionIndex - 1);
        s._pendingActionsQueue.clearAt(rawIndex);
        delete s._pendingActions[user];
    }

    /**
     * @notice Convert a `PendingAction` to a `DepositPendingAction`
     * @param action An untyped pending action
     * @return vaultAction_ The converted deposit pending action
     */
    function _toDepositPendingAction(PendingAction memory action)
        public
        pure
        returns (DepositPendingAction memory vaultAction_)
    {
        assembly {
            vaultAction_ := action
        }
    }

    /**
     * @notice Convert a `PendingAction` to a `WithdrawalPendingAction`
     * @param action An untyped pending action
     * @return vaultAction_ The converted withdrawal pending action
     */
    function _toWithdrawalPendingAction(PendingAction memory action)
        public
        pure
        returns (WithdrawalPendingAction memory vaultAction_)
    {
        assembly {
            vaultAction_ := action
        }
    }

    /**
     * @notice Convert a `PendingAction` to a `LongPendingAction`
     * @param action An untyped pending action
     * @return longAction_ The converted long pending action
     */
    function _toLongPendingAction(PendingAction memory action)
        public
        pure
        returns (LongPendingAction memory longAction_)
    {
        assembly {
            longAction_ := action
        }
    }

    /**
     * @notice Convert a `DepositPendingAction` to a `PendingAction`
     * @param action A deposit pending action
     * @return pendingAction_ The converted untyped pending action
     */
    function _convertDepositPendingAction(DepositPendingAction memory action)
        public
        pure
        returns (PendingAction memory pendingAction_)
    {
        assembly {
            pendingAction_ := action
        }
    }

    function _getOraclePrice(ProtocolAction action, uint256 timestamp, bytes calldata priceData)
        public
        payable
        returns (PriceInfo memory price_)
    {
        uint256 validationCost = s._oracleMiddleware.validationCost(priceData, action);
        if (address(this).balance < validationCost) {
            revert UsdnProtocolInsufficientOracleFee();
        }
        price_ =
            s._oracleMiddleware.parseAndValidatePrice{ value: validationCost }(uint128(timestamp), action, priceData);
    }

    /**
     * @notice Applies PnL, funding, and liquidates positions if necessary.
     * @param neutralPrice The neutral price for the asset.
     * @param timestamp The timestamp at which the operation is performed.
     * @param iterations The number of iterations for the liquidation process.
     * @param ignoreInterval A boolean indicating whether to ignore the interval for USDN rebase.
     * @param priceData The price oracle update data.
     * @return liquidatedPositions_ The number of positions that were liquidated.
     * @dev If there were any liquidated positions, it sends rewards to the msg.sender.
     */
    function _applyPnlAndFundingAndLiquidate(
        uint256 neutralPrice,
        uint256 timestamp,
        uint16 iterations,
        bool ignoreInterval,
        bytes memory priceData
    ) internal returns (uint256 liquidatedPositions_) {
        // adjust balances
        (bool priceUpdated, int256 tempLongBalance, int256 tempVaultBalance) =
            _applyPnlAndFunding(neutralPrice.toUint128(), timestamp.toUint128());

        // liquidate if price is more recent than _lastPrice
        if (priceUpdated) {
            LiquidationsEffects memory liquidationEffects =
                _liquidatePositions(neutralPrice, iterations, tempLongBalance, tempVaultBalance);

            s._balanceLong = liquidationEffects.newLongBalance;
            s._balanceVault = liquidationEffects.newVaultBalance;

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
     * @notice Liquidate positions which have a liquidation price lower than the current price
     * @param currentPrice The current price of the asset
     * @param iteration The maximum number of ticks to liquidate (minimum is 1)
     * @param tempLongBalance The temporary long balance as calculated when applying PnL and funding
     * @param tempVaultBalance The temporary vault balance as calculated when applying PnL and funding
     * @return effects_ The effects of the liquidations on the protocol
     */
    function _liquidatePositions(
        uint256 currentPrice,
        uint16 iteration,
        int256 tempLongBalance,
        int256 tempVaultBalance
    ) public returns (LiquidationsEffects memory effects_) {
        int256 longTradingExpo = s._totalExpo.toInt256() - tempLongBalance;
        if (longTradingExpo <= 0) {
            // In case the long balance is equal to the total expo (or exceeds it), the trading expo will become
            // zero.
            // In this case, it's not possible to calculate the current tick, so we can't perform any liquidations.
            (effects_.newLongBalance, effects_.newVaultBalance) =
                _handleNegativeBalances(tempLongBalance, tempVaultBalance);
            return effects_;
        }

        LiquidationData memory data;
        data.tempLongBalance = tempLongBalance;
        data.tempVaultBalance = tempVaultBalance;
        data.longTradingExpo = uint256(longTradingExpo);
        data.currentPrice = currentPrice;
        data.accumulator = s._liqMultiplierAccumulator;

        // max iteration limit
        if (iteration > s.MAX_LIQUIDATION_ITERATION) {
            iteration = s.MAX_LIQUIDATION_ITERATION;
        }

        uint256 unadjustedPrice =
            _unadjustPrice(data.currentPrice, data.currentPrice, data.longTradingExpo, data.accumulator);
        data.currentTick = TickMath.getClosestTickAtPrice(unadjustedPrice);
        data.iTick = s._highestPopulatedTick;

        do {
            uint256 index = s._tickBitmap.findLastSet(_calcBitmapIndexFromTick(data.iTick));
            if (index == LibBitmap.NOT_FOUND) {
                // no populated ticks left
                break;
            }

            data.iTick = _calcTickFromBitmapIndex(index);
            if (data.iTick < data.currentTick) {
                // all ticks that can be liquidated have been processed
                break;
            }

            // we have found a non-empty tick that needs to be liquidated
            (bytes32 tickHash,) = _tickHash(data.iTick);

            TickData memory tickData = s._tickData[tickHash];
            // Update transient data
            data.totalExpoToRemove += tickData.totalExpo;
            uint256 unadjustedTickPrice =
                TickMath.getPriceAtTick(data.iTick - int24(uint24(tickData.liquidationPenalty)) * s._tickSpacing);
            data.accumulatorValueToRemove += unadjustedTickPrice * tickData.totalExpo;
            // Update return values
            effects_.liquidatedPositions += tickData.totalPos;
            ++effects_.liquidatedTicks;
            int256 tickValue =
                _tickValue(data.iTick, data.currentPrice, data.longTradingExpo, data.accumulator, tickData);
            effects_.remainingCollateral += tickValue;

            // Reset tick by incrementing the tick version
            ++s._tickVersion[data.iTick];
            // Update bitmap to reflect that the tick is empty
            s._tickBitmap.unset(index);

            emit LiquidatedTick(
                data.iTick,
                s._tickVersion[data.iTick] - 1,
                data.currentPrice,
                getEffectivePriceForTick(data.iTick, data.currentPrice, data.longTradingExpo, data.accumulator),
                tickValue
            );
        } while (effects_.liquidatedTicks < iteration);

        data = _updateStateAfterLiquidation(data, effects_);

        (effects_.newLongBalance, effects_.newVaultBalance) =
            _handleNegativeBalances(data.tempLongBalance, data.tempVaultBalance);
    }

    /**
     * @notice Knowing the liquidation price of a position, get the corresponding unadjusted price, which can be used
     * to find the corresponding tick.
     * @param price An adjusted liquidation price (taking into account the effects of funding)
     * @param assetPrice The current price of the asset
     * @param longTradingExpo The trading expo of the long side (total expo - balance long)
     * @param accumulator The liquidation multiplier accumulator
     * @return unadjustedPrice_ The unadjusted price for the liquidation price
     */
    function _unadjustPrice(
        uint256 price,
        uint256 assetPrice,
        uint256 longTradingExpo,
        HugeUint.Uint512 memory accumulator
    ) public pure returns (uint256 unadjustedPrice_) {
        if (accumulator.hi == 0 && accumulator.lo == 0) {
            // no position in long, we assume a liquidation multiplier of 1.0
            return price;
        }
        if (longTradingExpo == 0) {
            // it is not possible to calculate the unadjusted price when the trading expo is zero
            revert UsdnProtocolZeroLongTradingExpo();
        }
        // M = assetPrice * (totalExpo - balanceLong) / accumulator
        // unadjustedPrice = price / M
        // unadjustedPrice = price * accumulator / (assetPrice * (totalExpo - balanceLong))
        HugeUint.Uint512 memory numerator = accumulator.mul(price);
        unadjustedPrice_ = numerator.div(assetPrice * longTradingExpo);
    }

    /**
     * @notice Calculate the value of a tick, knowing its contained total expo and the current asset price
     * @param tick The tick number
     * @param currentPrice The current price of the asset
     * @param longTradingExpo The trading expo of the long side
     * @param accumulator The liquidation multiplier accumulator
     * @param tickData The aggregate data for the tick
     * @return value_ The value of the tick (qty of asset tokens)
     */
    function _tickValue(
        int24 tick,
        uint256 currentPrice,
        uint256 longTradingExpo,
        HugeUint.Uint512 memory accumulator,
        TickData memory tickData
    ) public view returns (int256 value_) {
        uint128 liqPriceWithoutPenalty = getEffectivePriceForTick(
            _calcTickWithoutPenalty(tick, tickData.liquidationPenalty), currentPrice, longTradingExpo, accumulator
        );

        // value = totalExpo * (currentPrice - liqPriceWithoutPenalty) / currentPrice
        // if the current price is lower than the liquidation price, we have effectively a negative value
        if (currentPrice <= liqPriceWithoutPenalty) {
            // we calculate the inverse and then change the sign
            value_ = -int256(
                FixedPointMathLib.fullMulDiv(tickData.totalExpo, liqPriceWithoutPenalty - currentPrice, currentPrice)
            );
        } else {
            value_ = int256(
                FixedPointMathLib.fullMulDiv(tickData.totalExpo, currentPrice - liqPriceWithoutPenalty, currentPrice)
            );
        }
    }

    /**
     * @notice Calculate the tick without the liquidation penalty
     * @param tick The tick that holds the position
     * @param liquidationPenalty The liquidation penalty of the tick
     * @return tick_ The tick corresponding to the liquidation price without penalty
     */
    function _calcTickWithoutPenalty(int24 tick, uint8 liquidationPenalty) public view returns (int24 tick_) {
        tick_ = tick - int24(uint24(liquidationPenalty)) * s._tickSpacing;
    }

    function getEffectivePriceForTick(
        int24 tick,
        uint256 assetPrice,
        uint256 longTradingExpo,
        HugeUint.Uint512 memory accumulator
    ) public pure returns (uint128 price_) {
        price_ = _adjustPrice(TickMath.getPriceAtTick(tick), assetPrice, longTradingExpo, accumulator);
    }

    /**
     * @notice Knowing the unadjusted price for a tick, get the adjusted price taking into account the effects of the
     * funding.
     * @param unadjustedPrice The unadjusted price for the tick
     * @param assetPrice The current price of the asset
     * @param longTradingExpo The trading expo of the long side (total expo - balance long)
     * @param accumulator The liquidation multiplier accumulator
     * @return price_ The adjusted price for the tick
     */
    function _adjustPrice(
        uint256 unadjustedPrice,
        uint256 assetPrice,
        uint256 longTradingExpo,
        HugeUint.Uint512 memory accumulator
    ) public pure returns (uint128 price_) {
        if (accumulator.hi == 0 && accumulator.lo == 0) {
            // no position in long, we assume a liquidation multiplier of 1.0
            return unadjustedPrice.toUint128();
        }

        // M = assetPrice * (totalExpo - balanceLong) / accumulator
        // price = unadjustedPrice * M
        // price = unadjustedPrice * assetPrice * (totalExpo - balanceLong) / accumulator
        HugeUint.Uint512 memory numerator = HugeUint.mul(unadjustedPrice, assetPrice * longTradingExpo);
        price_ = numerator.div(accumulator).toUint128();
    }

    /**
     * @notice Update the state of the contract according to the liquidation effects
     * @param data The liquidation data
     * @param effects The effects of the liquidations
     * @return The updated liquidation data
     */
    function _updateStateAfterLiquidation(LiquidationData memory data, LiquidationsEffects memory effects)
        internal
        returns (LiquidationData memory)
    {
        // update the state
        s._totalLongPositions -= effects.liquidatedPositions;
        s._totalExpo -= data.totalExpoToRemove;
        s._liqMultiplierAccumulator = s._liqMultiplierAccumulator.sub(HugeUint.wrap(data.accumulatorValueToRemove));

        // keep track of the highest populated tick
        if (effects.liquidatedPositions != 0) {
            if (data.iTick < data.currentTick) {
                // all ticks above the current tick were liquidated
                s._highestPopulatedTick = _findHighestPopulatedTick(data.currentTick);
            } else {
                // unsure if all ticks above the current tick were liquidated, but some were
                s._highestPopulatedTick = _findHighestPopulatedTick(data.iTick);
            }
        }

        // Transfer remaining collateral to vault or pay bad debt
        data.tempLongBalance -= effects.remainingCollateral;
        data.tempVaultBalance += effects.remainingCollateral;

        return data;
    }

    /**
     * @notice Find the highest tick that contains at least one position
     * @dev If there are no ticks with a position left, returns minTick()
     * @param searchStart The tick from which to start searching
     * @return tick_ The next highest tick below `searchStart`
     */
    function _findHighestPopulatedTick(int24 searchStart) public view returns (int24 tick_) {
        uint256 index = s._tickBitmap.findLastSet(_calcBitmapIndexFromTick(searchStart));
        if (index == LibBitmap.NOT_FOUND) {
            tick_ = minTick();
        } else {
            tick_ = _calcTickFromBitmapIndex(index);
        }
    }

    /**
     * @dev Convert a Bitmap index to a signed tick using the tick spacing in storage
     * @param index The index into the Bitmap
     * @return tick_ The tick corresponding to the index, a multiple of the tick spacing
     */
    function _calcTickFromBitmapIndex(uint256 index) public view returns (int24 tick_) {
        tick_ = _calcTickFromBitmapIndex(index, s._tickSpacing);
    }

    /**
     * @dev Convert a Bitmap index to a signed tick using the provided tick spacing
     * @param index The index into the Bitmap
     * @param tickSpacing The tick spacing to use
     * @return tick_ The tick corresponding to the index, a multiple of `tickSpacing`
     */
    function _calcTickFromBitmapIndex(uint256 index, int24 tickSpacing) public pure returns (int24 tick_) {
        tick_ = int24( // cast to int24 is safe as index + TickMath.MIN_TICK cannot be above or below int24 limits
            (
                int256(index) // cast to int256 is safe as the index is lower than type(int24).max
                    + TickMath.MIN_TICK // shift into negative
                        / tickSpacing
            ) * tickSpacing
        );
    }

    function minTick() public view returns (int24 tick_) {
        tick_ = TickMath.minUsableTick(s._tickSpacing);
    }

    /**
     * @dev Convert a signed tick to an unsigned index into the Bitmap using the tick spacing in storage
     * @param tick The tick to convert, a multiple of the tick spacing
     * @return index_ The index into the Bitmap
     */
    function _calcBitmapIndexFromTick(int24 tick) public view returns (uint256 index_) {
        index_ = _calcBitmapIndexFromTick(tick, s._tickSpacing);
    }

    /**
     * @dev Convert a signed tick to an unsigned index into the Bitmap using the provided tick spacing
     * @param tick The tick to convert, a multiple of `tickSpacing`
     * @param tickSpacing The tick spacing to use
     * @return index_ The index into the Bitmap
     */
    function _calcBitmapIndexFromTick(int24 tick, int24 tickSpacing) public pure returns (uint256 index_) {
        index_ = uint256( // cast is safe as the min tick is always above TickMath.MIN_TICK
            (int256(tick) - TickMath.MIN_TICK) // shift into positive
                / tickSpacing
        );
    }

    /**
     * @notice Handle negative balances by transferring assets from one side to the other
     * @dev Balances are unsigned integers and can't be negative
     * In theory, this can not happen anymore because we have more precise calculations with the
     * `liqMultiplierAccumulator` compared to the old `liquidationMultiplier`
     * TODO: check if can be removed
     * @param tempLongBalance The temporary long balance after liquidations
     * @param tempVaultBalance The temporary vault balance after liquidations
     * @return longBalance_ The new long balance after rebalancing
     * @return vaultBalance_ The new vault balance after rebalancing
     */
    function _handleNegativeBalances(int256 tempLongBalance, int256 tempVaultBalance)
        internal
        pure
        returns (uint256 longBalance_, uint256 vaultBalance_)
    {
        // This can happen if the funding is larger than the remaining balance in the long side after applying PnL.
        // Test case: test_assetToTransferZeroBalance()
        if (tempLongBalance < 0) {
            tempVaultBalance += tempLongBalance;
            tempLongBalance = 0;
        }

        // This can happen if there is not enough balance in the vault to pay the bad debt of the long side, for
        // example if the protocol fees reduce the vault balance.
        // Test case: test_funding_NegLong_ZeroVault()
        if (tempVaultBalance < 0) {
            tempLongBalance += tempVaultBalance;
            tempVaultBalance = 0;
        }

        // TODO: remove safe cast once we're sure we can never have negative balances
        longBalance_ = tempLongBalance.toUint256();
        vaultBalance_ = tempVaultBalance.toUint256();
    }

    /**
     * @notice Check if a USDN rebase is required and adjust divisor if needed.
     * @dev Note: only call this function after `_applyPnlAndFunding` has been called to update the balances.
     * @param assetPrice The current price of the underlying asset
     * @param ignoreInterval If true, then the price check will be performed regardless of when the last check
     * happened
     * @return rebased_ Whether a rebase was performed
     */
    function _usdnRebase(uint128 assetPrice, bool ignoreInterval) public returns (bool rebased_) {
        if (!ignoreInterval && block.timestamp - s._lastRebaseCheck < s._usdnRebaseInterval) {
            return false;
        }
        s._lastRebaseCheck = block.timestamp;
        IUsdn usdn = s._usdn;
        uint256 divisor = usdn.divisor();
        if (divisor <= s._usdnMinDivisor) {
            // no need to rebase, the USDN divisor cannot go lower
            return false;
        }
        uint256 balanceVault = s._balanceVault;
        uint8 assetDecimals = s._assetDecimals;
        uint256 usdnTotalSupply = usdn.totalSupply();
        uint256 uPrice = _calcUsdnPrice(balanceVault, assetPrice, usdnTotalSupply, assetDecimals);
        if (uPrice <= s._usdnRebaseThreshold) {
            return false;
        }
        uint256 targetTotalSupply = _calcRebaseTotalSupply(balanceVault, assetPrice, s._targetUsdnPrice, assetDecimals);
        uint256 newDivisor = FixedPointMathLib.fullMulDiv(usdnTotalSupply, divisor, targetTotalSupply);
        usdn.rebase(newDivisor);
        rebased_ = true;
    }

    /**
     * @notice Calculate the price of the USDN token as a function of its total supply, the vault balance and the
     * underlying asset price.
     * @param vaultBalance The vault balance
     * @param assetPrice The price of the asset
     * @param usdnTotalSupply The total supply of the USDN token
     * @param assetDecimals The number of decimals of the underlying asset
     * @return price_ The price of the USDN token
     */
    function _calcUsdnPrice(uint256 vaultBalance, uint128 assetPrice, uint256 usdnTotalSupply, uint8 assetDecimals)
        public
        view
        returns (uint256 price_)
    {
        price_ = FixedPointMathLib.fullMulDiv(
            vaultBalance, uint256(assetPrice) * 10 ** s.TOKENS_DECIMALS, usdnTotalSupply * 10 ** assetDecimals
        );
    }

    /**
     * @notice Calculate the required USDN total supply to reach `targetPrice`
     * @param vaultBalance The balance of the vault
     * @param assetPrice The price of the underlying asset
     * @param targetPrice The target USDN price to reach
     * @param assetDecimals The number of decimals of the asset
     * @return totalSupply_ The required total supply to achieve `targetPrice`
     */
    function _calcRebaseTotalSupply(uint256 vaultBalance, uint128 assetPrice, uint128 targetPrice, uint8 assetDecimals)
        public
        view
        returns (uint256 totalSupply_)
    {
        totalSupply_ = FixedPointMathLib.fullMulDiv(
            vaultBalance, uint256(assetPrice) * 10 ** s.TOKENS_DECIMALS, uint256(targetPrice) * 10 ** assetDecimals
        );
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
            s._liquidationRewardsManager.getLiquidationRewards(liquidatedTicks, remainingCollateral, rebased, priceData);

        // Avoid underflows in situation of extreme bad debt
        if (s._balanceVault < liquidationRewards) {
            liquidationRewards = s._balanceVault;
        }

        // Update the vault's balance
        unchecked {
            s._balanceVault -= liquidationRewards;
        }

        // Transfer rewards (wsteth) to the liquidator
        s._asset.safeTransfer(msg.sender, liquidationRewards);

        emit LiquidatorRewarded(msg.sender, liquidationRewards);
    }

    /**
     * @notice Calculate the profits and losses of the long side, calculate the funding and apply protocol fees,
     * calculate the new liquidation multiplier and the temporary new balances for each side
     * @dev This function updates the state of `_lastPrice`, `_lastUpdateTimestamp`, `_lastFunding`, but does not
     * update the balances. This is left to the caller
     * @param currentPrice The current price
     * @param timestamp The timestamp of the current price
     * @return priceUpdated_ Whether the price was updated
     * @return tempLongBalance_ The new balance of the long side, could be negative (temporarily)
     * @return tempVaultBalance_ The new balance of the vault side, could be negative (temporarily)
     */
    function _applyPnlAndFunding(uint128 currentPrice, uint128 timestamp)
        public
        returns (bool priceUpdated_, int256 tempLongBalance_, int256 tempVaultBalance_)
    {
        // cache variable for optimization
        uint128 lastUpdateTimestamp = s._lastUpdateTimestamp;
        // if the price is not fresh, do nothing
        if (timestamp <= lastUpdateTimestamp) {
            return (false, s._balanceLong.toInt256(), s._balanceVault.toInt256());
        }

        // update the funding EMA
        int256 ema = _updateEMA(timestamp - lastUpdateTimestamp);

        // calculate the funding
        (int256 fundAsset, int256 fund) = _fundingAsset(timestamp, ema);

        // take protocol fee on the funding value
        (int256 fee, int256 fundWithFee, int256 fundAssetWithFee) = _calculateFee(fund, fundAsset);

        // we subtract the fee from the total balance
        int256 totalBalance = s._balanceLong.toInt256().safeAdd(s._balanceVault.toInt256()).safeSub(fee);
        // calculate new balances (for now, any bad debt has not been repaid, balances could become negative)

        if (fund > 0) {
            // in case of positive funding, the vault balance must be decremented by the totality of the funding amount
            // however, since we deducted the fee amount from the total balance, the vault balance will be incremented
            // only by the funding amount minus the fee amount
            tempLongBalance_ = _longAssetAvailable(currentPrice).safeSub(fundAsset);
        } else {
            // in case of negative funding, the vault balance must be decremented by the totality of the funding amount
            // however, since we deducted the fee amount from the total balance, the long balance will be incremented
            // only by the funding amount minus the fee amount
            tempLongBalance_ = _longAssetAvailable(currentPrice).safeSub(fundAssetWithFee);
        }
        tempVaultBalance_ = totalBalance.safeSub(tempLongBalance_);

        // update state variables
        s._lastPrice = currentPrice;
        s._lastUpdateTimestamp = timestamp;
        s._lastFunding = fundWithFee;

        priceUpdated_ = true;
    }

    /**
     * @notice Calculate the protocol fee and apply it to the funding asset amount
     * @dev The funding factor is only adjusted by the fee rate when the funding is negative (vault pays to the long
     * side)
     * @param fund The funding factor
     * @param fundAsset The funding asset amount to be used for the fee calculation
     * @return fee_ The absolute value of the calculated fee
     * @return fundWithFee_ The updated funding factor after applying the fee
     * @return fundAssetWithFee_ The updated funding asset amount after applying the fee
     */
    function _calculateFee(int256 fund, int256 fundAsset)
        internal
        returns (int256 fee_, int256 fundWithFee_, int256 fundAssetWithFee_)
    {
        int256 protocolFeeBps = _toInt256(s._protocolFeeBps);
        fundWithFee_ = fund;
        fee_ = fundAsset * protocolFeeBps / int256(s.BPS_DIVISOR);
        // fundAsset and fee_ have the same sign, we can safely subtract them to reduce the absolute amount of asset
        fundAssetWithFee_ = fundAsset - fee_;

        if (fee_ < 0) {
            // when funding is negative, the part that is taken as fees does not contribute to the liquidation
            // multiplier adjustment, and so we should deduce it from the funding factor
            fundWithFee_ -= fund * protocolFeeBps / int256(s.BPS_DIVISOR);
            // we want to return the absolute value of the fee
            fee_ = -fee_;
        }

        s._pendingProtocolFee += uint256(fee_);
    }

    /**
     * @notice Update the Exponential Moving Average (EMA) of the funding
     * @dev This function is called every time the protocol state is updated
     * @dev All required checks are done in the caller function (_applyPnlAndFunding)
     * @dev If the number of seconds elapsed is greater than or equal to the EMA period, the EMA is updated to the last
     * funding value
     * @param secondsElapsed The number of seconds elapsed since the last protocol action
     * @return The new EMA value
     */
    function _updateEMA(uint128 secondsElapsed) public returns (int256) {
        return s._EMA = calcEMA(s._lastFunding, secondsElapsed, s._EMAPeriod, s._EMA);
    }

    /**
     * @notice Clear the user pending action and return it
     * @param user The user's address
     * @return action_ The cleared pending action struct
     */
    function _getAndClearPendingAction(address user) internal returns (PendingAction memory action_) {
        uint128 rawIndex;
        (action_, rawIndex) = _getPendingActionOrRevert(user);
        s._pendingActionsQueue.clearAt(rawIndex);
        delete s._pendingActions[user];
    }

    /**
     * @notice Get the pending action for a user
     * @dev This function reverts if there is no pending action for the user
     * @param user The user's address
     * @return action_ The pending action struct
     * @return rawIndex_ The raw index of the pending action in the queue
     */
    function _getPendingActionOrRevert(address user)
        internal
        view
        returns (PendingAction memory action_, uint128 rawIndex_)
    {
        (action_, rawIndex_) = _getPendingAction(user);
        if (action_.action == ProtocolAction.None) {
            revert UsdnProtocolNoPendingAction();
        }
    }

    /**
     * @notice Get the pending action for a user
     * @dev To check for the presence of a pending action, compare `action_.action` to `ProtocolAction.None`. There is
     * a pending action only if the action is different from `ProtocolAction.None`
     * @param user The user's address
     * @return action_ The pending action struct if any, otherwise a zero-initialized struct
     * @return rawIndex_ The raw index of the pending action in the queue
     */
    function _getPendingAction(address user) public view returns (PendingAction memory action_, uint128 rawIndex_) {
        uint256 pendingActionIndex = s._pendingActions[user];
        // slither-disable-next-line incorrect-equality
        if (pendingActionIndex == 0) {
            // no pending action
            return (action_, rawIndex_);
        }

        rawIndex_ = uint128(pendingActionIndex - 1);
        action_ = s._pendingActionsQueue.atRaw(rawIndex_);
    }

    /**
     * @notice Add a pending action to the queue
     * @dev This reverts if there is already a pending action for this user
     * @param user The user's address
     * @param action The pending action struct
     * @return securityDepositValue_ The security deposit value of the stale pending action
     */
    function _addPendingAction(address user, PendingAction memory action)
        public
        returns (uint256 securityDepositValue_)
    {
        securityDepositValue_ = _removeStalePendingAction(user); // check if there is a pending action that was
            // liquidated and remove it
        if (s._pendingActions[user] > 0) {
            revert UsdnProtocolPendingAction();
        }
        // Add the action to the queue
        uint128 rawIndex = s._pendingActionsQueue.pushBack(action);
        // Store the index shifted by one, so that zero means no pending action
        s._pendingActions[user] = uint256(rawIndex) + 1;
    }

    /**
     * @notice Remove the pending action from the queue if its tick version doesn't match the current tick version
     * @dev This is only applicable to `ValidateOpenPosition` pending actions
     * @param user The user's address
     * @return securityDepositValue_ The security deposit value of the removed stale pending action
     */
    function _removeStalePendingAction(address user) internal returns (uint256 securityDepositValue_) {
        // slither-disable-next-line incorrect-equality
        if (s._pendingActions[user] == 0) {
            return 0;
        }
        (PendingAction memory action, uint128 rawIndex) = _getPendingAction(user);
        // the position is only at risk of being liquidated while pending if it is an open position action
        // slither-disable-next-line incorrect-equality
        if (action.action == ProtocolAction.ValidateOpenPosition) {
            LongPendingAction memory openAction = _toLongPendingAction(action);
            (, uint256 version) = _tickHash(openAction.tick);
            if (version != openAction.tickVersion) {
                securityDepositValue_ = openAction.securityDepositValue;
                // the position was liquidated while pending
                // remove the stale pending action
                s._pendingActionsQueue.clearAt(rawIndex);
                delete s._pendingActions[user];
                emit StalePendingActionRemoved(
                    user,
                    PositionId({ tick: openAction.tick, tickVersion: openAction.tickVersion, index: openAction.index })
                );
            }
        }
    }
}

// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.25;

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { LibBitmap } from "solady/src/utils/LibBitmap.sol";
import { FixedPointMathLib } from "solady/src/utils/FixedPointMathLib.sol";

import { IUsdnProtocolLong } from "../interfaces/UsdnProtocol/IUsdnProtocolLong.sol";
import { Position, LiquidationsEffects, TickData, PositionId } from "../interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import { UsdnProtocolVault } from "./UsdnProtocolVault.sol";
import { TickMath } from "../libraries/TickMath.sol";
import { SignedMath } from "../libraries/SignedMath.sol";
import { HugeUint } from "../libraries/HugeUint.sol";

abstract contract UsdnProtocolLong is IUsdnProtocolLong, UsdnProtocolVault {
    using LibBitmap for LibBitmap.Bitmap;
    using SafeCast for uint256;
    using SafeCast for int256;
    using SignedMath for int256;
    using HugeUint for HugeUint.Uint512;

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
     * @param isLiquidationPending Whether some ticks are still populated above the current price (left to liquidate)
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
        bool isLiquidationPending;
    }

    /// @inheritdoc IUsdnProtocolLong
    function minTick() public view returns (int24 tick_) {
        tick_ = TickMath.minUsableTick(_tickSpacing);
    }

    /// @inheritdoc IUsdnProtocolLong
    function maxTick() external view returns (int24 tick_) {
        tick_ = TickMath.maxUsableTick(_tickSpacing);
    }

    /// @inheritdoc IUsdnProtocolLong
    function getLongPosition(PositionId memory posId)
        public
        view
        returns (Position memory pos_, uint8 liquidationPenalty_)
    {
        (bytes32 tickHash, uint256 version) = _tickHash(posId.tick);
        if (posId.tickVersion != version) {
            revert UsdnProtocolOutdatedTick(version, posId.tickVersion);
        }
        pos_ = _longPositions[tickHash][posId.index];
        liquidationPenalty_ = _tickData[tickHash].liquidationPenalty;
    }

    /// @inheritdoc IUsdnProtocolLong
    // slither-disable-next-line write-after-write
    function getMinLiquidationPrice(uint128 price) external view returns (uint128 liquidationPrice_) {
        liquidationPrice_ = _getLiquidationPrice(price, uint128(_minLeverage));
        int24 tick = getEffectiveTickForPrice(liquidationPrice_);
        liquidationPrice_ = getEffectivePriceForTick(tick + _tickSpacing);
    }

    /// @inheritdoc IUsdnProtocolLong
    function getPositionValue(PositionId calldata posId, uint128 price, uint128 timestamp)
        external
        view
        returns (int256 value_)
    {
        (Position memory pos, uint8 liquidationPenalty) = getLongPosition(posId);
        int256 longTradingExpo = longTradingExpoWithFunding(price, timestamp);
        if (longTradingExpo < 0) {
            // in case the long balance is equal to the total expo (or exceeds it), the trading expo will become zero
            // in this case, the liquidation price will fall to zero, and the position value will be equal to its
            // total expo (initial collateral * initial leverage)
            longTradingExpo = 0;
        }
        uint128 liqPrice = getEffectivePriceForTick(
            _calcTickWithoutPenalty(posId.tick, liquidationPenalty),
            price,
            uint256(longTradingExpo),
            _liqMultiplierAccumulator
        );
        value_ = _positionValue(price, liqPrice, pos.totalExpo);
    }

    /// @inheritdoc IUsdnProtocolLong
    function getEffectiveTickForPrice(uint128 price) public view returns (int24 tick_) {
        tick_ = getEffectiveTickForPrice(
            price, _lastPrice, _totalExpo - _balanceLong, _liqMultiplierAccumulator, _tickSpacing
        );
    }

    /// @inheritdoc IUsdnProtocolLong
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

    /// @inheritdoc IUsdnProtocolLong
    function getEffectivePriceForTick(int24 tick) public view returns (uint128 price_) {
        price_ = getEffectivePriceForTick(tick, _lastPrice, _totalExpo - _balanceLong, _liqMultiplierAccumulator);
    }

    /// @inheritdoc IUsdnProtocolLong
    function getEffectivePriceForTick(
        int24 tick,
        uint256 assetPrice,
        uint256 longTradingExpo,
        HugeUint.Uint512 memory accumulator
    ) public pure returns (uint128 price_) {
        price_ = _adjustPrice(TickMath.getPriceAtTick(tick), assetPrice, longTradingExpo, accumulator);
    }

    /**
     * @notice Variant of `getEffectivePriceForTick` when a fixed precision representation of the liquidation multiplier
     * is known
     * @param tick The tick number
     * @param liqMultiplier The liquidation price multiplier, with LIQUIDATION_MULTIPLIER_DECIMALS decimals
     * @return price_ The adjusted price for the tick
     */
    function _getEffectivePriceForTick(int24 tick, uint256 liqMultiplier) internal pure returns (uint128 price_) {
        price_ = _adjustPrice(TickMath.getPriceAtTick(tick), liqMultiplier);
    }

    /**
     * @notice Knowing the liquidation price of a position, get the corresponding unadjusted price, which can be used
     * to find the corresponding tick
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
    ) internal pure returns (uint256 unadjustedPrice_) {
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
     * @notice Knowing the unadjusted price for a tick, get the adjusted price taking into account the effects of the
     * funding
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
    ) internal pure returns (uint128 price_) {
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
     * @notice Variant of _adjustPrice when a fixed precision representation of the liquidation multiplier is known
     * @param unadjustedPrice The unadjusted price for the tick
     * @param liqMultiplier The liquidation price multiplier, with LIQUIDATION_MULTIPLIER_DECIMALS decimals
     * @return price_ The adjusted price for the tick
     */
    function _adjustPrice(uint256 unadjustedPrice, uint256 liqMultiplier) internal pure returns (uint128 price_) {
        // price = unadjustedPrice * M
        price_ = FixedPointMathLib.fullMulDiv(unadjustedPrice, liqMultiplier, 10 ** LIQUIDATION_MULTIPLIER_DECIMALS)
            .toUint128();
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
    ) internal pure returns (uint256 multiplier_) {
        if (accumulator.hi == 0 && accumulator.lo == 0) {
            // no position in long, we assume a liquidation multiplier of 1.0
            return 10 ** LIQUIDATION_MULTIPLIER_DECIMALS;
        }
        // M = assetPrice * (totalExpo - balanceLong) / accumulator
        HugeUint.Uint512 memory numerator =
            HugeUint.mul(10 ** LIQUIDATION_MULTIPLIER_DECIMALS, assetPrice * longTradingExpo);
        multiplier_ = numerator.div(accumulator);
    }

    /**
     * @notice Find the highest tick that contains at least one position
     * @dev If there are no ticks with a position left, returns minTick()
     * @param searchStart The tick from which to start searching
     * @return tick_ The next highest tick below `searchStart`
     */
    function _findHighestPopulatedTick(int24 searchStart) internal view returns (int24 tick_) {
        uint256 index = _tickBitmap.findLastSet(_calcBitmapIndexFromTick(searchStart));
        if (index == LibBitmap.NOT_FOUND) {
            tick_ = minTick();
        } else {
            tick_ = _calcTickFromBitmapIndex(index);
        }
    }

    /**
     * @notice Calculate the theoretical liquidation price of a position knowing its start price and leverage
     * @param startPrice Entry price of the position
     * @param leverage Leverage of the position
     * @return price_ The liquidation price of the position
     */
    function _getLiquidationPrice(uint128 startPrice, uint128 leverage) internal pure returns (uint128 price_) {
        price_ = (startPrice - ((uint256(10) ** LEVERAGE_DECIMALS * startPrice) / leverage)).toUint128();
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
        internal
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
    ) internal view returns (int256 value_) {
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
     * @notice Calculate the leverage of a position, knowing its start price and liquidation price
     * @dev This does not take into account the liquidation penalty
     * @param startPrice Entry price of the position
     * @param liquidationPrice Liquidation price of the position
     * @return leverage_ The leverage of the position
     */
    function _getLeverage(uint128 startPrice, uint128 liquidationPrice) internal pure returns (uint128 leverage_) {
        if (startPrice <= liquidationPrice) {
            // this situation is not allowed (newly open position must be solvent)
            // also, the calculation below would underflow
            revert UsdnProtocolInvalidLiquidationPrice(liquidationPrice, startPrice);
        }

        leverage_ = ((10 ** LEVERAGE_DECIMALS * uint256(startPrice)) / (startPrice - liquidationPrice)).toUint128();
    }

    /**
     * @notice Calculate the total exposure of a position
     * @dev Reverts when startPrice <= liquidationPrice
     * @param amount The amount of asset used as collateral
     * @param startPrice The price of the asset when the position was created
     * @param liquidationPrice The liquidation price of the position
     * @return totalExpo_ The total exposure of a position
     */
    function _calcPositionTotalExpo(uint128 amount, uint128 startPrice, uint128 liquidationPrice)
        internal
        pure
        returns (uint128 totalExpo_)
    {
        if (startPrice <= liquidationPrice) {
            revert UsdnProtocolInvalidLiquidationPrice(liquidationPrice, startPrice);
        }

        totalExpo_ = FixedPointMathLib.fullMulDiv(amount, startPrice, startPrice - liquidationPrice).toUint128();
    }

    /**
     * @notice Calculate the liquidation price without penalty of a position to reach a certain trading expo
     * @dev If the sum of `amount` and `tradingExpo` equals 0, reverts
     * @param currentPrice The price of the asset
     * @param amount The amount of asset
     * @param tradingExpo The trading expo
     * @return liqPrice_ The liquidation price without penalty
     */
    function _calcLiqPriceFromTradingExpo(uint128 currentPrice, uint128 amount, uint256 tradingExpo)
        internal
        pure
        returns (uint128 liqPrice_)
    {
        uint256 totalExpo = amount + tradingExpo;
        if (totalExpo == 0) {
            revert UsdnProtocolZeroTotalExpo();
        }

        liqPrice_ = FixedPointMathLib.fullMulDiv(currentPrice, tradingExpo, totalExpo).toUint128();
    }

    /**
     * @notice Check if the safety margin is respected
     * @dev Reverts if not respected
     * @param currentPrice The current price of the asset
     * @param liquidationPrice The liquidation price of the position
     */
    function _checkSafetyMargin(uint128 currentPrice, uint128 liquidationPrice) internal view {
        uint128 maxLiquidationPrice = (currentPrice * (BPS_DIVISOR - _safetyMarginBps) / BPS_DIVISOR).toUint128();
        if (liquidationPrice >= maxLiquidationPrice) {
            revert UsdnProtocolLiquidationPriceSafetyMargin(liquidationPrice, maxLiquidationPrice);
        }
    }

    /**
     * @notice Save a new position in the protocol, adjusting the tick data and global variables
     * @dev Note: this method does not update the long balance
     * @param tick The tick to hold the new position
     * @param long The position to save
     * @param liquidationPenalty The liquidation penalty for the tick
     * @return tickVersion_ The version of the tick
     * @return index_ The index of the position in the tick array
     * @return liqMultiplierAccumulator_ The updated liquidation multiplier accumulator
     */
    function _saveNewPosition(int24 tick, Position memory long, uint8 liquidationPenalty)
        internal
        returns (uint256 tickVersion_, uint256 index_, HugeUint.Uint512 memory liqMultiplierAccumulator_)
    {
        bytes32 tickHash;
        (tickHash, tickVersion_) = _tickHash(tick);

        // add to tick array
        Position[] storage tickArray = _longPositions[tickHash];
        index_ = tickArray.length;
        if (tick > _highestPopulatedTick) {
            // keep track of the highest populated tick
            _highestPopulatedTick = tick;
        }
        tickArray.push(long);

        // adjust state
        _totalExpo += long.totalExpo;
        ++_totalLongPositions;

        // update tick data
        TickData storage tickData = _tickData[tickHash];
        // the unadjusted tick price for the accumulator might be different depending
        // if we already have positions in the tick or not
        uint256 unadjustedTickPrice;
        if (tickData.totalPos == 0) {
            // first position in this tick, we need to reflect that it is populated
            _tickBitmap.set(_calcBitmapIndexFromTick(tick));
            // we store the data for this tick
            tickData.totalExpo = long.totalExpo;
            tickData.totalPos = 1;
            tickData.liquidationPenalty = liquidationPenalty;
            unadjustedTickPrice = TickMath.getPriceAtTick(tick - int24(uint24(liquidationPenalty)) * _tickSpacing);
        } else {
            tickData.totalExpo += long.totalExpo;
            tickData.totalPos += 1;
            // we do not need to adjust the tick's `liquidationPenalty` since it remains constant
            unadjustedTickPrice =
                TickMath.getPriceAtTick(tick - int24(uint24(tickData.liquidationPenalty)) * _tickSpacing);
        }
        // update the accumulator with the correct tick price (depending on the liquidation penalty value)
        liqMultiplierAccumulator_ = _liqMultiplierAccumulator.add(HugeUint.wrap(unadjustedTickPrice * long.totalExpo));
        _liqMultiplierAccumulator = liqMultiplierAccumulator_;
    }

    /**
     * @notice Remove the provided total amount from its position and update the tick data and position
     * @dev Note: this method does not update the long balance
     * If the amount to remove is greater than or equal to the position's total amount, the position is deleted instead
     * @param tick The tick to remove from
     * @param index Index of the position in the tick array
     * @param pos The position to remove the amount from
     * @param amountToRemove The amount to remove from the position
     * @param totalExpoToRemove The total expo to remove from the position
     * @return liqMultiplierAccumulator_ The updated liquidation multiplier accumulator
     */
    function _removeAmountFromPosition(
        int24 tick,
        uint256 index,
        Position memory pos,
        uint128 amountToRemove,
        uint128 totalExpoToRemove
    ) internal returns (HugeUint.Uint512 memory liqMultiplierAccumulator_) {
        (bytes32 tickHash,) = _tickHash(tick);
        TickData storage tickData = _tickData[tickHash];
        uint256 unadjustedTickPrice =
            TickMath.getPriceAtTick(tick - int24(uint24(tickData.liquidationPenalty)) * _tickSpacing);
        if (amountToRemove < pos.amount) {
            Position storage position = _longPositions[tickHash][index];
            position.totalExpo = pos.totalExpo - totalExpoToRemove;

            unchecked {
                position.amount = pos.amount - amountToRemove;
            }
        } else {
            totalExpoToRemove = pos.totalExpo;
            tickData.totalPos -= 1;
            --_totalLongPositions;

            // remove from tick array (set to zero to avoid shifting indices)
            delete _longPositions[tickHash][index];
            if (tickData.totalPos == 0) {
                // we removed the last position in the tick
                _tickBitmap.unset(_calcBitmapIndexFromTick(tick));
            }
        }

        _totalExpo -= totalExpoToRemove;
        tickData.totalExpo -= totalExpoToRemove;
        liqMultiplierAccumulator_ =
            _liqMultiplierAccumulator.sub(HugeUint.wrap(unadjustedTickPrice * totalExpoToRemove));
        _liqMultiplierAccumulator = liqMultiplierAccumulator_;
    }

    /// @inheritdoc IUsdnProtocolLong
    function getTickLiquidationPenalty(int24 tick) public view returns (uint8 liquidationPenalty_) {
        (bytes32 tickHash,) = _tickHash(tick);
        liquidationPenalty_ = _getTickLiquidationPenalty(tickHash);
    }

    /**
     * @notice Retrieve the liquidation penalty assigned to the tick and version corresponding to `tickHash`, if there
     * are positions in it, otherwise retrieve the current setting value from storage
     * @dev This method allows to reuse a pre-computed tickHash if available
     * @param tickHash The tick hash
     * @return liquidationPenalty_ The liquidation penalty, in tick spacing units
     */
    function _getTickLiquidationPenalty(bytes32 tickHash) internal view returns (uint8 liquidationPenalty_) {
        TickData storage tickData = _tickData[tickHash];
        liquidationPenalty_ = tickData.totalPos != 0 ? tickData.liquidationPenalty : _liquidationPenalty;
    }

    /**
     * @dev Convert a Bitmap index to a signed tick using the tick spacing in storage
     * @param index The index into the Bitmap
     * @return tick_ The tick corresponding to the index, a multiple of the tick spacing
     */
    function _calcTickFromBitmapIndex(uint256 index) internal view returns (int24 tick_) {
        tick_ = _calcTickFromBitmapIndex(index, _tickSpacing);
    }

    /**
     * @dev Convert a Bitmap index to a signed tick using the provided tick spacing
     * @param index The index into the Bitmap
     * @param tickSpacing The tick spacing to use
     * @return tick_ The tick corresponding to the index, a multiple of `tickSpacing`
     */
    function _calcTickFromBitmapIndex(uint256 index, int24 tickSpacing) internal pure returns (int24 tick_) {
        tick_ = int24( // cast to int24 is safe as index + TickMath.MIN_TICK cannot be above or below int24 limits
            (
                int256(index) // cast to int256 is safe as the index is lower than type(int24).max
                    + TickMath.MIN_TICK // shift into negative
                        / tickSpacing
            ) * tickSpacing
        );
    }

    /**
     * @notice Calculate the tick without the liquidation penalty
     * @param tick The tick that holds the position
     * @param liquidationPenalty The liquidation penalty of the tick
     * @return tick_ The tick corresponding to the liquidation price without penalty
     */
    function _calcTickWithoutPenalty(int24 tick, uint8 liquidationPenalty) internal view returns (int24 tick_) {
        tick_ = tick - int24(uint24(liquidationPenalty)) * _tickSpacing;
    }

    /**
     * @notice Liquidate positions that have a liquidation price lower than the current price
     * @param currentPrice The current price of the asset
     * @param iteration The maximum number of ticks to liquidate (minimum is 1)
     * @param tempLongBalance The temporary long balance as calculated when applying the PnL and funding
     * @param tempVaultBalance The temporary vault balance as calculated when applying the PnL and funding
     * @return effects_ The effects of the liquidations on the protocol
     */
    function _liquidatePositions(
        uint256 currentPrice,
        uint16 iteration,
        int256 tempLongBalance,
        int256 tempVaultBalance
    ) internal returns (LiquidationsEffects memory effects_) {
        int256 longTradingExpo = _totalExpo.toInt256() - tempLongBalance;
        if (longTradingExpo <= 0) {
            // in case the long balance is equal to the total expo (or exceeds it), the trading expo will become zero
            // in this case, it's not possible to calculate the current tick, so we can't perform any liquidations
            (effects_.newLongBalance, effects_.newVaultBalance) =
                _handleNegativeBalances(tempLongBalance, tempVaultBalance);
            return effects_;
        }

        LiquidationData memory data;
        data.tempLongBalance = tempLongBalance;
        data.tempVaultBalance = tempVaultBalance;
        data.longTradingExpo = uint256(longTradingExpo);
        data.currentPrice = currentPrice;
        data.accumulator = _liqMultiplierAccumulator;

        // max iteration limit
        if (iteration > MAX_LIQUIDATION_ITERATION) {
            iteration = MAX_LIQUIDATION_ITERATION;
        }

        uint256 unadjustedPrice =
            _unadjustPrice(data.currentPrice, data.currentPrice, data.longTradingExpo, data.accumulator);
        data.currentTick = TickMath.getClosestTickAtPrice(unadjustedPrice);
        data.iTick = _highestPopulatedTick;

        do {
            uint256 index = _tickBitmap.findLastSet(_calcBitmapIndexFromTick(data.iTick));
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

            TickData memory tickData = _tickData[tickHash];
            // update transient data
            data.totalExpoToRemove += tickData.totalExpo;
            uint256 unadjustedTickPrice =
                TickMath.getPriceAtTick(data.iTick - int24(uint24(tickData.liquidationPenalty)) * _tickSpacing);
            data.accumulatorValueToRemove += unadjustedTickPrice * tickData.totalExpo;
            // update return values
            effects_.liquidatedPositions += tickData.totalPos;
            ++effects_.liquidatedTicks;
            int256 tickValue =
                _tickValue(data.iTick, data.currentPrice, data.longTradingExpo, data.accumulator, tickData);
            effects_.remainingCollateral += tickValue;

            // reset tick by incrementing the tick version
            ++_tickVersion[data.iTick];
            // update bitmap to reflect that the tick is empty
            _tickBitmap.unset(index);

            emit LiquidatedTick(
                data.iTick,
                _tickVersion[data.iTick] - 1,
                data.currentPrice,
                getEffectivePriceForTick(data.iTick, data.currentPrice, data.longTradingExpo, data.accumulator),
                tickValue
            );
        } while (effects_.liquidatedTicks < iteration);

        _updateStateAfterLiquidation(data, effects_); // mutates `data`
        effects_.isLiquidationPending = data.isLiquidationPending;
        (effects_.newLongBalance, effects_.newVaultBalance) =
            _handleNegativeBalances(data.tempLongBalance, data.tempVaultBalance);
    }

    /**
     * @notice Update the state of the contract according to the liquidation effects
     * @param data The liquidation data, which gets mutated by the function
     * @param effects The effects of the liquidations
     */
    function _updateStateAfterLiquidation(LiquidationData memory data, LiquidationsEffects memory effects) internal {
        // update the state
        _totalLongPositions -= effects.liquidatedPositions;
        _totalExpo -= data.totalExpoToRemove;
        _liqMultiplierAccumulator = _liqMultiplierAccumulator.sub(HugeUint.wrap(data.accumulatorValueToRemove));

        // keep track of the highest populated tick
        if (effects.liquidatedPositions != 0) {
            if (data.iTick < data.currentTick) {
                // all ticks above the current tick were liquidated
                _highestPopulatedTick = _findHighestPopulatedTick(data.currentTick);
            } else {
                // unsure if all ticks above the current tick were liquidated, but some were
                int24 highestPopulatedTick = _findHighestPopulatedTick(data.iTick);
                _highestPopulatedTick = highestPopulatedTick;
                data.isLiquidationPending = data.currentTick <= highestPopulatedTick;
            }
        }

        // transfer remaining collateral to vault or pay bad debt
        data.tempLongBalance -= effects.remainingCollateral;
        data.tempVaultBalance += effects.remainingCollateral;
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
        // this can happen if the funding is larger than the remaining balance in the long side after applying PnL
        // test case: test_assetToTransferZeroBalance()
        if (tempLongBalance < 0) {
            tempVaultBalance += tempLongBalance;
            tempLongBalance = 0;
        }

        // this can happen if there is not enough balance in the vault to pay the bad debt in the long side, for
        // example if the protocol fees reduce the vault balance
        // test case: test_funding_NegLong_ZeroVault()
        if (tempVaultBalance < 0) {
            tempLongBalance += tempVaultBalance;
            tempVaultBalance = 0;
        }

        // TODO: remove safe cast once we're sure we can never have negative balances
        longBalance_ = tempLongBalance.toUint256();
        vaultBalance_ = tempVaultBalance.toUint256();
    }

    /**
     * @notice Calculates the current imbalance between the vault and long sides
     * @dev If the value is positive, the long trading expo is smaller than the vault trading expo
     * If the trading expo is equal to 0, the imbalance is infinite and int256.max is returned
     * @param vaultBalance The balance of the vault
     * @param longBalance The balance of the long side
     * @param totalExpo The total expo of the long side
     * @return imbalanceBps_ The imbalance in basis points
     */
    function _calcImbalanceCloseBps(int256 vaultBalance, int256 longBalance, uint256 totalExpo)
        internal
        pure
        returns (int256 imbalanceBps_)
    {
        int256 tradingExpo = totalExpo.toInt256().safeSub(longBalance);
        if (tradingExpo == 0) {
            return type(int256).max;
        }

        // imbalanceBps_ = (vaultBalance - (totalExpo - longBalance)) * BPS_DIVISOR / (totalExpo - longBalance);
        imbalanceBps_ = (vaultBalance.safeSub(tradingExpo)).safeMul(int256(BPS_DIVISOR)).safeDiv(tradingExpo);
    }

    /**
     * TODO add tests
     * @notice Immediately close a position with the given price
     * @dev Should only be used to close the rebalancer position
     * @param posId The ID of the position to close
     * @param neutralPrice The current neutral price
     * @param cache The cached state of the protocol, will be updated during this call
     * @return positionValue_ The value of the closed position. If 0, the position was/will be liquidated
     */
    function _flashClosePosition(PositionId memory posId, uint128 neutralPrice, CachedProtocolState memory cache)
        internal
        returns (uint256 positionValue_)
    {
        (bytes32 tickHash, uint256 version) = _tickHash(posId.tick);
        // if the tick version is outdated, the position was liquidated and its value is 0
        if (posId.tickVersion != version) {
            return positionValue_;
        }

        uint8 liquidationPenalty = _tickData[tickHash].liquidationPenalty;
        Position memory pos = _longPositions[tickHash][posId.index];

        // fully close the position and update the cache
        cache.liqMultiplierAccumulator =
            _removeAmountFromPosition(posId.tick, posId.index, pos, pos.amount, pos.totalExpo);

        int256 positionValue = _positionValue(
            neutralPrice,
            getEffectivePriceForTick(
                _calcTickWithoutPenalty(posId.tick, liquidationPenalty),
                neutralPrice,
                cache.tradingExpo,
                cache.liqMultiplierAccumulator
            ),
            pos.totalExpo
        );

        // if positionValue is lower than 0, return 0
        if (positionValue < 0) {
            return positionValue_;
        }

        // cast is safe as positionValue cannot be lower than 0
        positionValue_ = uint256(positionValue);

        // update the cache
        cache.totalExpo -= pos.totalExpo;
        cache.longBalance -= positionValue_;
        cache.tradingExpo = cache.totalExpo - cache.longBalance;

        // emit both initiate and validate events
        // so the position is considered the same as other positions by event indexers
        emit InitiatedClosePosition(pos.user, pos.user, pos.user, posId, pos.amount, pos.amount, 0);
        emit ValidatedClosePosition(pos.user, pos.user, posId, positionValue_, positionValue - _toInt256(pos.amount));
    }

    /**
     * TODO add tests
     * @notice Immediately open a position with the given price
     * @dev Should only be used to open the rebalancer position
     * @param user The address of the user
     * @param neutralPrice The current neutral price
     * @param tickWithoutPenalty The tick the position should be opened in
     * @param amount The amount of collateral in the position
     * @param cache The cached state of the protocol
     * @return posId_ The ID of the position that was created
     */
    function _flashOpenPosition(
        address user,
        uint128 neutralPrice,
        int24 tickWithoutPenalty,
        uint128 amount,
        CachedProtocolState memory cache
    ) internal returns (PositionId memory posId_) {
        // we calculate the closest valid tick down for the desired liquidation price with the liquidation penalty
        uint8 currentLiqPenalty = _liquidationPenalty;

        posId_.tick = tickWithoutPenalty + int24(uint24(currentLiqPenalty)) * _tickSpacing;

        uint8 liquidationPenalty = getTickLiquidationPenalty(posId_.tick);
        uint128 liqPriceWithoutPenalty;

        // check if the penalty for that tick is different from the current setting
        // this can happen if the setting has been changed, but the position is added in a tick that was never empty
        // after the said change, so the first value is still applied
        if (liquidationPenalty == currentLiqPenalty) {
            liqPriceWithoutPenalty = getEffectivePriceForTick(
                tickWithoutPenalty, neutralPrice, cache.tradingExpo, cache.liqMultiplierAccumulator
            );
        } else {
            liqPriceWithoutPenalty = getEffectivePriceForTick(
                _calcTickWithoutPenalty(posId_.tick, liquidationPenalty),
                neutralPrice,
                cache.tradingExpo,
                cache.liqMultiplierAccumulator
            );
        }

        uint128 totalExpo = _calcPositionTotalExpo(amount, neutralPrice, liqPriceWithoutPenalty);
        Position memory long = Position({
            validated: true,
            user: user,
            amount: amount,
            totalExpo: totalExpo,
            timestamp: uint40(block.timestamp)
        });

        // save the position on the provided tick
        (posId_.tickVersion, posId_.index,) = _saveNewPosition(posId_.tick, long, liquidationPenalty);

        // emit both initiate and validate events
        // so the position is considered the same as other positions by event indexers
        emit InitiatedOpenPosition(user, user, uint40(block.timestamp), totalExpo, long.amount, neutralPrice, posId_);
        emit ValidatedOpenPosition(user, user, totalExpo, neutralPrice, posId_);
    }

    /**
     * @notice Calculates the tick of the rebalancer position to open
     * @dev The returned tick must be higher than or equal to the minimum leverage of the protocol
     * and lower than or equal to the rebalancer and USDN protocol leverages (lower of the 2)
     * @param neutralPrice The neutral asset price
     * @param positionAmount The amount of assets in the position
     * @param rebalancerMaxLeverage The max leverage supported by the rebalancer
     * @param cache The cached protocol state values
     * @return tickWithoutLiqPenalty_ The tick where the position will be saved
     */
    function _calcRebalancerPositionTick(
        uint128 neutralPrice,
        uint128 positionAmount,
        uint256 rebalancerMaxLeverage,
        CachedProtocolState memory cache
    ) internal view returns (int24 tickWithoutLiqPenalty_) {
        // use the lowest max leverage above the min leverage
        uint256 protocolMinLeverage = _minLeverage;
        {
            uint256 protocolMaxLeverage = _maxLeverage;
            if (rebalancerMaxLeverage > protocolMaxLeverage) {
                rebalancerMaxLeverage = protocolMaxLeverage;
            }
            if (rebalancerMaxLeverage < protocolMinLeverage) {
                rebalancerMaxLeverage = protocolMinLeverage;
            }
        }

        int256 longImbalanceTargetBps = _longImbalanceTargetBps;
        // calculate the trading expo missing to reach the imbalance target
        uint256 targetTradingExpo =
            (cache.vaultBalance * BPS_DIVISOR / (int256(BPS_DIVISOR) + longImbalanceTargetBps).toUint256());

        // check that the target is not already exceeded
        if (cache.tradingExpo >= targetTradingExpo) {
            return NO_POSITION_TICK;
        }

        uint256 tradingExpoToFill = targetTradingExpo - cache.tradingExpo;

        // check that the trading expo filled by the position would not exceed the max leverage
        uint256 highestUsableTradingExpo =
            positionAmount * rebalancerMaxLeverage / 10 ** LEVERAGE_DECIMALS - positionAmount;
        if (highestUsableTradingExpo < tradingExpoToFill) {
            tradingExpoToFill = highestUsableTradingExpo;
        }

        {
            // check that the trading expo filled by the position would not be below the min leverage
            uint256 lowestUsableTradingExpo =
                positionAmount * protocolMinLeverage / 10 ** LEVERAGE_DECIMALS - positionAmount;
            if (lowestUsableTradingExpo > tradingExpoToFill) {
                tradingExpoToFill = lowestUsableTradingExpo;
            }
        }

        tickWithoutLiqPenalty_ = getEffectiveTickForPrice(
            _calcLiqPriceFromTradingExpo(neutralPrice, positionAmount, tradingExpoToFill),
            neutralPrice,
            cache.tradingExpo,
            cache.liqMultiplierAccumulator,
            _tickSpacing
        );

        // calculate the total expo of the position that will be created with the tick
        uint256 positionTotalExpo = _calcPositionTotalExpo(
            positionAmount,
            neutralPrice,
            getEffectivePriceForTick(
                tickWithoutLiqPenalty_, neutralPrice, cache.tradingExpo, cache.liqMultiplierAccumulator
            )
        );

        // due to the rounding down, if the imbalance is still greater than the desired imbalance
        // and the position is not at the max leverage, add one tick
        if (
            highestUsableTradingExpo != tradingExpoToFill
                && _calcImbalanceCloseBps(
                    cache.vaultBalance.toInt256(),
                    (cache.longBalance + positionAmount).toInt256(),
                    cache.totalExpo + positionTotalExpo
                ) > longImbalanceTargetBps
        ) {
            tickWithoutLiqPenalty_ += _tickSpacing;
        }
    }
}

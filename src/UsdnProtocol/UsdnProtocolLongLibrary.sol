// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.25;

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { LibBitmap } from "solady/src/utils/LibBitmap.sol";
import { FixedPointMathLib } from "solady/src/utils/FixedPointMathLib.sol";

import { IUsdnProtocolLong } from "../interfaces/UsdnProtocol/IUsdnProtocolLong.sol";
import { Position, LiquidationsEffects, TickData, PositionId } from "../interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import { TickMath } from "../libraries/TickMath.sol";
import { SignedMath } from "../libraries/SignedMath.sol";
import { HugeUint } from "../libraries/HugeUint.sol";
import { Storage, CachedProtocolState } from "./UsdnProtocolBaseStorage.sol";
import { UsdnProtocolVaultLibrary as vaultLib } from "./UsdnProtocolVaultLibrary.sol";
import { UsdnProtocolCoreLibrary as coreLib } from "./UsdnProtocolCoreLibrary.sol";
import { IUsdnProtocolErrors } from "./../interfaces/UsdnProtocol/IUsdnProtocolErrors.sol";

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

library UsdnProtocolLongLibrary {
    using LibBitmap for LibBitmap.Bitmap;
    using SafeCast for uint256;
    using SafeCast for int256;
    using SignedMath for int256;
    using HugeUint for HugeUint.Uint512;

    // / @inheritdoc IUsdnProtocolLong
    function minTick(Storage storage s) public view returns (int24 tick_) {
        tick_ = TickMath.minUsableTick(s._tickSpacing);
    }

    // / @inheritdoc IUsdnProtocolLong
    function maxTick(Storage storage s) external view returns (int24 tick_) {
        tick_ = TickMath.maxUsableTick(s._tickSpacing);
    }

    // / @inheritdoc IUsdnProtocolLong
    function getLongPosition(Storage storage s, PositionId memory posId)
        public
        view
        returns (Position memory pos_, uint8 liquidationPenalty_)
    {
        (bytes32 tickHash, uint256 version) = vaultLib._tickHash(s, posId.tick);
        if (posId.tickVersion != version) {
            revert IUsdnProtocolErrors.UsdnProtocolOutdatedTick(version, posId.tickVersion);
        }
        pos_ = s._longPositions[tickHash][posId.index];
        liquidationPenalty_ = s._tickData[tickHash].liquidationPenalty;
    }

    // / @inheritdoc IUsdnProtocolLong
    // slither-disable-next-line write-after-write
    function getMinLiquidationPrice(Storage storage s, uint128 price)
        external
        view
        returns (uint128 liquidationPrice_)
    {
        liquidationPrice_ = _getLiquidationPrice(s, price, uint128(s._minLeverage));
        int24 tick = getEffectiveTickForPrice(s, liquidationPrice_);
        liquidationPrice_ = getEffectivePriceForTick(s, tick + s._tickSpacing);
    }

    // / @inheritdoc IUsdnProtocolLong
    function getPositionValue(Storage storage s, PositionId calldata posId, uint128 price, uint128 timestamp)
        external
        view
        returns (int256 value_)
    {
        (Position memory pos, uint8 liquidationPenalty) = getLongPosition(s, posId);
        int256 longTradingExpo = longTradingExpoWithFunding(s, price, timestamp);
        if (longTradingExpo < 0) {
            // in case the long balance is equal to the total expo (or exceeds it), the trading expo will become zero
            // in this case, the liquidation price will fall to zero, and the position value will be equal to its
            // total expo (initial collateral * initial leverage)
            longTradingExpo = 0;
        }
        uint128 liqPrice = getEffectivePriceForTick(
            _calcTickWithoutPenalty(s, posId.tick, liquidationPenalty),
            price,
            uint256(longTradingExpo),
            s._liqMultiplierAccumulator
        );
        value_ = _positionValue(price, liqPrice, pos.totalExpo);
    }

    // / @inheritdoc IUsdnProtocolLong
    function getEffectiveTickForPrice(Storage storage s, uint128 price) public view returns (int24 tick_) {
        tick_ = getEffectiveTickForPrice(
            price, s._lastPrice, s._totalExpo - s._balanceLong, s._liqMultiplierAccumulator, s._tickSpacing
        );
    }

    // / @inheritdoc IUsdnProtocolLong
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

    // / @inheritdoc IUsdnProtocolLong
    function getEffectivePriceForTick(Storage storage s, int24 tick) public view returns (uint128 price_) {
        price_ =
            getEffectivePriceForTick(tick, s._lastPrice, s._totalExpo - s._balanceLong, s._liqMultiplierAccumulator);
    }

    // / @inheritdoc IUsdnProtocolLong
    function getEffectivePriceForTick(
        int24 tick,
        uint256 assetPrice,
        uint256 longTradingExpo,
        HugeUint.Uint512 memory accumulator
    ) public pure returns (uint128 price_) {
        price_ = _adjustPrice(TickMath.getPriceAtTick(tick), assetPrice, longTradingExpo, accumulator);
    }

    // / @inheritdoc IUsdnProtocolCore
    function longAssetAvailableWithFunding(Storage storage s, uint128 currentPrice, uint128 timestamp)
        public
        view
        returns (int256 available_)
    {
        if (timestamp < s._lastUpdateTimestamp) {
            revert IUsdnProtocolErrors.UsdnProtocolTimestampTooOld();
        }

        int256 ema = coreLib.calcEMA(s._lastFunding, timestamp - s._lastUpdateTimestamp, s._EMAPeriod, s._EMA);
        (int256 fundAsset,) = coreLib._fundingAsset(s, timestamp, ema);

        if (fundAsset > 0) {
            available_ = coreLib._longAssetAvailable(s, currentPrice).safeSub(fundAsset);
        } else {
            int256 fee = fundAsset * coreLib._toInt256(s._protocolFeeBps) / int256(s.BPS_DIVISOR);
            // fees have the same sign as fundAsset (negative here), so we need to sub them
            available_ = coreLib._longAssetAvailable(s, currentPrice).safeSub(fundAsset - fee);
        }
    }

    // / @inheritdoc IUsdnProtocolCore
    function longTradingExpoWithFunding(Storage storage s, uint128 currentPrice, uint128 timestamp)
        public
        view
        returns (int256 expo_)
    {
        expo_ = s._totalExpo.toInt256().safeSub(longAssetAvailableWithFunding(s, currentPrice, timestamp));
    }

    // / @inheritdoc IUsdnProtocolLong
    function getTickLiquidationPenalty(Storage storage s, int24 tick) public view returns (uint8 liquidationPenalty_) {
        (bytes32 tickHash,) = vaultLib._tickHash(s, tick);
        liquidationPenalty_ = _getTickLiquidationPenalty(s, tickHash);
    }

    /**
     * @notice Variant of `getEffectivePriceForTick` when a fixed precision representation of the liquidation multiplier
     * is known
     * @param tick The tick number
     * @param liqMultiplier The liquidation price multiplier, with LIQUIDATION_MULTIPLIER_DECIMALS decimals
     * @return price_ The adjusted price for the tick
     */
    function _getEffectivePriceForTick(Storage storage s, int24 tick, uint256 liqMultiplier)
        internal
        view
        returns (uint128 price_)
    {
        price_ = _adjustPrice(s, TickMath.getPriceAtTick(tick), liqMultiplier);
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
            revert IUsdnProtocolErrors.UsdnProtocolZeroLongTradingExpo();
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
    function _adjustPrice(Storage storage s, uint256 unadjustedPrice, uint256 liqMultiplier)
        internal
        view
        returns (uint128 price_)
    {
        // price = unadjustedPrice * M
        price_ = FixedPointMathLib.fullMulDiv(unadjustedPrice, liqMultiplier, 10 ** s.LIQUIDATION_MULTIPLIER_DECIMALS)
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
        Storage storage s,
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

    /**
     * @notice Find the highest tick that contains at least one position
     * @dev If there are no ticks with a position left, returns minTick()
     * @param searchStart The tick from which to start searching
     * @return tick_ The next highest tick below `searchStart`
     */
    function _findHighestPopulatedTick(Storage storage s, int24 searchStart) internal view returns (int24 tick_) {
        uint256 index = s._tickBitmap.findLastSet(coreLib._calcBitmapIndexFromTick(s, searchStart));
        if (index == LibBitmap.NOT_FOUND) {
            tick_ = minTick(s);
        } else {
            tick_ = _calcTickFromBitmapIndex(s, index);
        }
    }

    /**
     * @notice Calculate the theoretical liquidation price of a position knowing its start price and leverage
     * @param startPrice Entry price of the position
     * @param leverage Leverage of the position
     * @return price_ The liquidation price of the position
     */
    function _getLiquidationPrice(Storage storage s, uint128 startPrice, uint128 leverage)
        internal
        view
        returns (uint128 price_)
    {
        price_ = (startPrice - ((uint256(10) ** s.LEVERAGE_DECIMALS * startPrice) / leverage)).toUint128();
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
        Storage storage s,
        int24 tick,
        uint256 currentPrice,
        uint256 longTradingExpo,
        HugeUint.Uint512 memory accumulator,
        TickData memory tickData
    ) internal view returns (int256 value_) {
        uint128 liqPriceWithoutPenalty = getEffectivePriceForTick(
            _calcTickWithoutPenalty(s, tick, tickData.liquidationPenalty), currentPrice, longTradingExpo, accumulator
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
    function _getLeverage(Storage storage s, uint128 startPrice, uint128 liquidationPrice)
        internal
        view
        returns (uint128 leverage_)
    {
        if (startPrice <= liquidationPrice) {
            // this situation is not allowed (newly open position must be solvent)
            // also, the calculation below would underflow
            revert IUsdnProtocolErrors.UsdnProtocolInvalidLiquidationPrice(liquidationPrice, startPrice);
        }

        leverage_ = ((10 ** s.LEVERAGE_DECIMALS * uint256(startPrice)) / (startPrice - liquidationPrice)).toUint128();
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
            revert IUsdnProtocolErrors.UsdnProtocolInvalidLiquidationPrice(liquidationPrice, startPrice);
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
            revert IUsdnProtocolErrors.UsdnProtocolZeroTotalExpo();
        }

        liqPrice_ = FixedPointMathLib.fullMulDiv(currentPrice, tradingExpo, totalExpo).toUint128();
    }

    /**
     * @notice Check if the safety margin is respected
     * @dev Reverts if not respected
     * @param currentPrice The current price of the asset
     * @param liquidationPrice The liquidation price of the position
     */
    function _checkSafetyMargin(Storage storage s, uint128 currentPrice, uint128 liquidationPrice) internal view {
        uint128 maxLiquidationPrice = (currentPrice * (s.BPS_DIVISOR - s._safetyMarginBps) / s.BPS_DIVISOR).toUint128();
        if (liquidationPrice >= maxLiquidationPrice) {
            revert IUsdnProtocolErrors.UsdnProtocolLiquidationPriceSafetyMargin(liquidationPrice, maxLiquidationPrice);
        }
    }

    /**
     * @notice Retrieve the liquidation penalty assigned to the tick and version corresponding to `tickHash`, if there
     * are positions in it, otherwise retrieve the current setting value from storage
     * @dev This method allows to reuse a pre-computed tickHash if available
     * @param tickHash The tick hash
     * @return liquidationPenalty_ The liquidation penalty, in tick spacing units
     */
    function _getTickLiquidationPenalty(Storage storage s, bytes32 tickHash)
        internal
        view
        returns (uint8 liquidationPenalty_)
    {
        TickData storage tickData = s._tickData[tickHash];
        liquidationPenalty_ = tickData.totalPos != 0 ? tickData.liquidationPenalty : s._liquidationPenalty;
    }

    /**
     * @dev Convert a Bitmap index to a signed tick using the tick spacing in storage
     * @param index The index into the Bitmap
     * @return tick_ The tick corresponding to the index, a multiple of the tick spacing
     */
    function _calcTickFromBitmapIndex(Storage storage s, uint256 index) internal view returns (int24 tick_) {
        tick_ = _calcTickFromBitmapIndex(index, s._tickSpacing);
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
    function _calcTickWithoutPenalty(Storage storage s, int24 tick, uint8 liquidationPenalty)
        internal
        view
        returns (int24 tick_)
    {
        tick_ = tick - int24(uint24(liquidationPenalty)) * s._tickSpacing;
    }

    /**
     * @notice Update the state of the contract according to the liquidation effects
     * @param data The liquidation data, which gets mutated by the function
     * @param effects The effects of the liquidations
     */
    function _updateStateAfterLiquidation(
        Storage storage s,
        LiquidationData memory data,
        LiquidationsEffects memory effects
    ) internal {
        // update the state
        s._totalLongPositions -= effects.liquidatedPositions;
        s._totalExpo -= data.totalExpoToRemove;
        s._liqMultiplierAccumulator = s._liqMultiplierAccumulator.sub(HugeUint.wrap(data.accumulatorValueToRemove));

        // keep track of the highest populated tick
        if (effects.liquidatedPositions != 0) {
            if (data.iTick < data.currentTick) {
                // all ticks above the current tick were liquidated
                s._highestPopulatedTick = _findHighestPopulatedTick(s, data.currentTick);
            } else {
                // unsure if all ticks above the current tick were liquidated, but some were
                int24 highestPopulatedTick = _findHighestPopulatedTick(s, data.iTick);
                s._highestPopulatedTick = highestPopulatedTick;
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
    function _calcImbalanceCloseBps(Storage storage s, int256 vaultBalance, int256 longBalance, uint256 totalExpo)
        internal
        view
        returns (int256 imbalanceBps_)
    {
        int256 tradingExpo = totalExpo.toInt256().safeSub(longBalance);
        if (tradingExpo == 0) {
            return type(int256).max;
        }

        // imbalanceBps_ = (vaultBalance - (totalExpo - longBalance)) *s. (totalExpo - longBalance);
        imbalanceBps_ = (vaultBalance.safeSub(tradingExpo)).safeMul(int256(s.BPS_DIVISOR)).safeDiv(tradingExpo);
    }

    /**
     * TODO add tests
     * @notice Calculates the current imbalance for the open action checks
     * @dev If the value is positive, the long trading expo is larger than the vault trading expo
     * In case of zero vault balance, the function returns `int256.max` since the resulting imbalance would be infinity
     * @param vaultBalance The balance of the vault
     * @param longBalance The balance of the long side (including the long position to open)
     * @param totalExpo The total expo of the long side (including the long position to open)
     * @return imbalanceBps_ The imbalance in basis points
     */
    function _calcImbalanceOpenBps(Storage storage s, int256 vaultBalance, int256 longBalance, uint256 totalExpo)
        internal
        view
        returns (int256 imbalanceBps_)
    {
        // avoid division by zero
        if (vaultBalance == 0) {
            return type(int256).max;
        }
        // imbalanceBps_ = ((totalExpo - longBalance) - vaultBalance) *s. vaultBalance;
        int256 longTradingExpo = totalExpo.toInt256() - longBalance;
        imbalanceBps_ = longTradingExpo.safeSub(vaultBalance).safeMul(int256(s.BPS_DIVISOR)).safeDiv(vaultBalance);
    }

    /**
     * @notice Calculates the tick of the rebalancer position to open
     * @dev The returned tick must be higher than or equal to the minimum leverage of the protocol
     * and lower than or equal to the rebalancer and USDN protocol leverages (lower of the 2)
     * @param lastPrice The last price used to update the protocol
     * @param positionAmount The amount of assets in the position
     * @param rebalancerMaxLeverage The max leverage supported by the rebalancer
     * @param cache The cached protocol state values
     * @return tickWithoutLiqPenalty_ The tick where the position will be saved
     */
    function _calcRebalancerPositionTick(
        Storage storage s,
        uint128 lastPrice,
        uint128 positionAmount,
        uint256 rebalancerMaxLeverage,
        CachedProtocolState memory cache
    ) internal view returns (int24 tickWithoutLiqPenalty_) {
        // use the lowest max leverage above the min leverage
        uint256 protocolMinLeverage = s._minLeverage;
        {
            uint256 protocolMaxLeverage = s._maxLeverage;
            if (rebalancerMaxLeverage > protocolMaxLeverage) {
                rebalancerMaxLeverage = protocolMaxLeverage;
            }
            if (rebalancerMaxLeverage < protocolMinLeverage) {
                rebalancerMaxLeverage = protocolMinLeverage;
            }
        }

        int256 longImbalanceTargetBps = s._longImbalanceTargetBps;
        // calculate the trading expo missing to reach the imbalance target
        uint256 targetTradingExpo =
            (cache.vaultBalance * s.BPS_DIVISOR / (int256(s.BPS_DIVISOR) + longImbalanceTargetBps).toUint256());

        // check that the target is not already exceeded
        if (cache.tradingExpo >= targetTradingExpo) {
            return s.NO_POSITION_TICK;
        }

        uint256 tradingExpoToFill = targetTradingExpo - cache.tradingExpo;

        // check that the trading expo filled by the position would not exceed the max leverage
        uint256 highestUsableTradingExpo =
            positionAmount * rebalancerMaxLeverage / 10 ** s.LEVERAGE_DECIMALS - positionAmount;
        if (highestUsableTradingExpo < tradingExpoToFill) {
            tradingExpoToFill = highestUsableTradingExpo;
        }

        {
            // check that the trading expo filled by the position would not be below the min leverage
            uint256 lowestUsableTradingExpo =
                positionAmount * protocolMinLeverage / 10 ** s.LEVERAGE_DECIMALS - positionAmount;
            if (lowestUsableTradingExpo > tradingExpoToFill) {
                tradingExpoToFill = lowestUsableTradingExpo;
            }
        }

        tickWithoutLiqPenalty_ = getEffectiveTickForPrice(
            _calcLiqPriceFromTradingExpo(lastPrice, positionAmount, tradingExpoToFill),
            lastPrice,
            cache.tradingExpo,
            cache.liqMultiplierAccumulator,
            s._tickSpacing
        );

        // calculate the total expo of the position that will be created with the tick
        uint256 positionTotalExpo = _calcPositionTotalExpo(
            positionAmount,
            lastPrice,
            getEffectivePriceForTick(
                tickWithoutLiqPenalty_, lastPrice, cache.tradingExpo, cache.liqMultiplierAccumulator
            )
        );

        // due to the rounding down, if the imbalance is still greater than the desired imbalance
        // and the position is not at the max leverage, add one tick
        if (
            highestUsableTradingExpo != tradingExpoToFill
                && _calcImbalanceCloseBps(
                    s,
                    cache.vaultBalance.toInt256(),
                    (cache.longBalance + positionAmount).toInt256(),
                    cache.totalExpo + positionTotalExpo
                ) > longImbalanceTargetBps
        ) {
            tickWithoutLiqPenalty_ += s._tickSpacing;
        }
    }
}

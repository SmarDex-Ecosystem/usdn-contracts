// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { LibBitmap } from "solady/src/utils/LibBitmap.sol";
import { FixedPointMathLib } from "solady/src/utils/FixedPointMathLib.sol";

import { IUsdnProtocolLong } from "src/interfaces/UsdnProtocol/IUsdnProtocolLong.sol";
import { Position } from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import { UsdnProtocolVault } from "src/UsdnProtocol/UsdnProtocolVault.sol";
import { TickMath } from "src/libraries/TickMath.sol";
import { SignedMath } from "src/libraries/SignedMath.sol";

abstract contract UsdnProtocolLong is IUsdnProtocolLong, UsdnProtocolVault {
    using LibBitmap for LibBitmap.Bitmap;
    using SafeCast for uint256;
    using SafeCast for int256;
    using SignedMath for int256;

    /// @inheritdoc IUsdnProtocolLong
    function getMinTick() public view returns (int24 tick_) {
        tick_ = TickMath.minUsableTick(_tickSpacing);
    }

    /// @inheritdoc IUsdnProtocolLong
    function getMaxTick() public view returns (int24 tick_) {
        tick_ = TickMath.maxUsableTick(_tickSpacing);
    }

    /// @inheritdoc IUsdnProtocolLong
    function getLongPosition(int24 tick, uint256 tickVersion, uint256 index)
        public
        view
        returns (Position memory pos_)
    {
        (bytes32 tickHash, uint256 version) = _getTickHash(tick);
        if (tickVersion != version) {
            revert UsdnProtocolOutdatedTick(version, tickVersion);
        }
        pos_ = _longPositions[tickHash][index];
    }

    /// @inheritdoc IUsdnProtocolLong
    function getLongPositionsLength(int24 tick) external view returns (uint256 len_) {
        (bytes32 tickHash,) = _getTickHash(tick);
        len_ = _positionsInTick[tickHash];
    }

    /// @inheritdoc IUsdnProtocolLong
    // slither-disable-next-line write-after-write
    function getMinLiquidationPrice(uint128 price) public view returns (uint128 liquidationPrice_) {
        liquidationPrice_ = _getLiquidationPrice(price, uint128(_minLeverage));
        int24 tick = getEffectiveTickForPrice(liquidationPrice_);
        liquidationPrice_ = getEffectivePriceForTick(tick + _tickSpacing);
    }

    /// @inheritdoc IUsdnProtocolLong
    function getPositionValue(int24 tick, uint256 tickVersion, uint256 index, uint128 currentPrice)
        external
        view
        returns (uint256 value_)
    {
        Position memory pos = getLongPosition(tick, tickVersion, index);
        uint128 liqPrice = getEffectivePriceForTick(tick - int24(_liquidationPenalty) * _tickSpacing);
        value_ = _getPositionValue(currentPrice, liqPrice, pos.amount, pos.leverage);
    }

    /// @inheritdoc IUsdnProtocolLong
    function getEffectiveTickForPrice(uint128 price) public view returns (int24 tick_) {
        // adjusted price with liquidation multiplier
        uint256 priceWithMultiplier =
            FixedPointMathLib.fullMulDiv(price, 10 ** LIQUIDATION_MULTIPLIER_DECIMALS, _liquidationMultiplier);

        if (priceWithMultiplier < TickMath.MIN_PRICE) {
            return getMinTick();
        }

        int24 tickSpacing = _tickSpacing;
        tick_ = TickMath.getTickAtPrice(priceWithMultiplier);

        // round down to the next valid tick according to _tickSpacing (towards negative infinity)
        if (tick_ < 0) {
            // we round up the inverse number (positive) then invert it -> round towards negative infinity
            tick_ = -int24(int256(FixedPointMathLib.divUp(uint256(int256(-tick_)), uint256(int256(tickSpacing)))))
                * tickSpacing;
            // avoid invalid ticks
            int24 minUsableTick = getMinTick();
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
        // adjusted price with liquidation multiplier
        price_ = _getEffectivePriceForTick(tick, _liquidationMultiplier);
    }

    function _getEffectivePriceForTick(int24 tick, uint256 liqMultiplier) internal pure returns (uint128 price_) {
        // adjusted price with liquidation multiplier
        price_ = FixedPointMathLib.fullMulDiv(
            TickMath.getPriceAtTick(tick), liqMultiplier, 10 ** LIQUIDATION_MULTIPLIER_DECIMALS
        ).toUint128();
    }

    /**
     * @notice Get the largest tick which contains at least one position
     * @param searchStart The tick from which to start searching
     */
    function _getMaxInitializedTick(int24 searchStart) internal view returns (int24 tick_) {
        uint256 index = _tickBitmap.findLastSet(_getTickToBitmapIndex(searchStart));
        if (index == LibBitmap.NOT_FOUND) {
            tick_ = getMinTick();
        } else {
            tick_ = _getBitmapIndexToTick(index);
        }
    }

    /**
     * @notice Calculate the theoretical liquidation price of a position knowing its start price and leverage
     * @param startPrice Entry price of the position
     * @param leverage Leverage of the position
     */
    function _getLiquidationPrice(uint128 startPrice, uint128 leverage) internal pure returns (uint128 price_) {
        price_ = (startPrice - ((uint256(10) ** LEVERAGE_DECIMALS * startPrice) / leverage)).toUint128();
    }

    /**
     * @notice Calculate the value of a position, knowing its liquidation price and the current asset price
     * @param currentPrice The current price of the asset
     * @param liqPriceWithoutPenalty The liquidation price of the position without the liquidation penalty
     * @param amount The amount of the position
     * @param initLeverage The initial leverage of the position
     */
    function _getPositionValue(
        uint128 currentPrice,
        uint128 liqPriceWithoutPenalty,
        uint256 amount,
        uint128 initLeverage
    ) internal pure returns (uint256 value_) {
        if (currentPrice < liqPriceWithoutPenalty) {
            return 0;
        }
        // totalExpo = amount * initLeverage
        // value = totalExpo * (currentPrice - liqPriceWithoutPenalty) / currentPrice
        value_ = FixedPointMathLib.fullMulDiv(
            amount,
            uint256(initLeverage) * (currentPrice - liqPriceWithoutPenalty),
            currentPrice * uint256(10) ** LEVERAGE_DECIMALS
        );
    }

    /**
     * @notice Calculate the value of a tick, knowing its contained total expo and the current asset price
     * @param currentPrice The current price of the asset
     * @param tick The tick number
     * @param tickTotalExpo The total expo of the positions in the tick
     */
    function _getTickValue(uint256 currentPrice, int24 tick, uint256 tickTotalExpo)
        internal
        view
        returns (int256 value_)
    {
        // value = totalExpo * (currentPrice - liqPriceWithoutPenalty) / currentPrice
        uint128 liqPriceWithoutPenalty = getEffectivePriceForTick(tick - int24(_liquidationPenalty) * _tickSpacing);

        // if the current price is lower than the liquidation price, we have effectively a negative value
        if (currentPrice <= liqPriceWithoutPenalty) {
            // we calculate the inverse and then change the sign
            value_ = -int256(FixedPointMathLib.fullMulDiv(tickTotalExpo, liqPriceWithoutPenalty - currentPrice, currentPrice));
        } else {
            value_ =
                int256(FixedPointMathLib.fullMulDiv(tickTotalExpo, currentPrice - liqPriceWithoutPenalty, currentPrice));
        }
    }

    /// @dev This does not take into account the liquidation penalty
    function _getLeverage(uint128 startPrice, uint128 liquidationPrice) internal pure returns (uint128 leverage_) {
        if (startPrice <= liquidationPrice) {
            // this situation is not allowed (newly open position must be solvent)
            // Also, calculation below would underflow
            revert UsdnProtocolInvalidLiquidationPrice(liquidationPrice, startPrice);
        }

        leverage_ = ((10 ** LEVERAGE_DECIMALS * uint256(startPrice)) / (startPrice - liquidationPrice)).toUint128();
    }

    function _getMaxLiquidationPriceWithSafetyMargin(uint128 price)
        internal
        view
        returns (uint128 maxLiquidationPrice_)
    {
        maxLiquidationPrice_ = uint128(price * (BPS_DIVISOR - _safetyMarginBps) / BPS_DIVISOR);
    }

    function _checkSafetyMargin(uint128 currentPrice, uint128 liquidationPrice) internal view {
        uint128 maxLiquidationPrice = _getMaxLiquidationPriceWithSafetyMargin(currentPrice);
        if (liquidationPrice >= maxLiquidationPrice) {
            revert UsdnProtocolLiquidationPriceSafetyMargin(liquidationPrice, maxLiquidationPrice);
        }
    }

    function _saveNewPosition(int24 tick, Position memory long)
        internal
        returns (uint256 tickVersion_, uint256 index_)
    {
        bytes32 tickHash;
        (tickHash, tickVersion_) = _getTickHash(tick);

        // Adjust state
        _balanceLong += long.amount;
        uint256 addExpo = FixedPointMathLib.fullMulDiv(long.amount, long.leverage, 10 ** LEVERAGE_DECIMALS);
        _totalExpo += addExpo;
        _totalExpoByTick[tickHash] += addExpo;
        ++_positionsInTick[tickHash];
        ++_totalLongPositions;

        // Add to tick array
        Position[] storage tickArray = _longPositions[tickHash];
        index_ = tickArray.length;
        if (_positionsInTick[tickHash] == 1) {
            // first position in this tick, we need to reflect that it is populated
            _tickBitmap.set(_getTickToBitmapIndex(tick));
        }
        if (tick > _maxInitializedTick) {
            // keep track of max initialized tick
            _maxInitializedTick = tick;
        }
        tickArray.push(long);
    }

    function _removePosition(int24 tick, uint256 tickVersion, uint256 index) internal returns (Position memory pos_) {
        (bytes32 tickHash, uint256 version) = _getTickHash(tick);

        if (version != tickVersion) {
            revert UsdnProtocolOutdatedTick(version, tickVersion);
        }

        Position[] storage tickArray = _longPositions[tickHash];
        pos_ = tickArray[index];

        // Adjust state
        uint256 removeExpo = FixedPointMathLib.fullMulDiv(pos_.amount, pos_.leverage, 10 ** LEVERAGE_DECIMALS);
        _totalExpo -= removeExpo;
        _totalExpoByTick[tickHash] -= removeExpo;
        --_positionsInTick[tickHash];
        --_totalLongPositions;

        // Remove from tick array (set to zero to avoid shifting indices)
        delete tickArray[index];
        if (_positionsInTick[tickHash] == 0) {
            // we removed the last position in the tick
            _tickBitmap.unset(_getTickToBitmapIndex(tick));
        }
    }

    /**
     * @dev Convert a signed tick to an unsigned index into the Bitmap
     * @param tick The tick to convert, a multiple of `tickSpacing`
     * @return index_ The index into the Bitmap
     */
    function _getTickToBitmapIndex(int24 tick) internal view returns (uint256 index_) {
        int24 compactTick = tick / _tickSpacing;
        // shift into positive and cast to uint256
        index_ = uint256(int256(compactTick) - int256(type(int24).min));
    }

    /**
     * @dev Convert a Bitmap index to a signed tick
     * @param index The index into the Bitmap
     * @return tick_ The tick corresponding to the index, a multiple of `tickSpacing`
     */
    function _getBitmapIndexToTick(uint256 index) internal view returns (int24 tick_) {
        // cast to int256 and shift into negative
        int24 compactTick = (int256(index) + int256(type(int24).min)).toInt24();
        tick_ = compactTick * _tickSpacing;
    }

    function _liquidatePositions(uint256 currentPrice, uint16 iteration)
        internal
        returns (uint256 liquidatedPositions_, uint16 liquidatedTicks_, int256 remainingCollateral_)
    {
        // max iteration limit
        if (iteration > MAX_LIQUIDATION_ITERATION) {
            iteration = MAX_LIQUIDATION_ITERATION;
        }

        uint256 priceWithMultiplier =
            FixedPointMathLib.fullMulDiv(currentPrice, 10 ** LIQUIDATION_MULTIPLIER_DECIMALS, _liquidationMultiplier);
        int24 currentTick = TickMath.getClosestTickAtPrice(priceWithMultiplier);
        int24 tick = _maxInitializedTick;

        do {
            uint256 index = _tickBitmap.findLastSet(_getTickToBitmapIndex(tick));
            if (index == LibBitmap.NOT_FOUND) {
                // no populated ticks left
                break;
            }

            tick = _getBitmapIndexToTick(index);
            if (tick < currentTick) {
                break;
            }

            // we have found a non-empty tick that needs to be liquidated
            (bytes32 tickHash,) = _getTickHash(tick);
            uint256 length = _positionsInTick[tickHash];

            uint256 tickTotalExpo = _totalExpoByTick[tickHash];
            int256 tickValue = _getTickValue(currentPrice, tick, tickTotalExpo);
            remainingCollateral_ += tickValue;
            unchecked {
                _totalExpo -= tickTotalExpo;

                _totalLongPositions -= length;
                liquidatedPositions_ += length;

                ++_tickVersion[tick];
                ++liquidatedTicks_;
            }
            _tickBitmap.unset(_getTickToBitmapIndex(tick));

            emit LiquidatedTick(tick, _tickVersion[tick] - 1, currentPrice, getEffectivePriceForTick(tick), tickValue);
        } while (liquidatedTicks_ < iteration);

        if (liquidatedPositions_ != 0) {
            if (tick < currentTick) {
                // all ticks above the current tick were liquidated
                _maxInitializedTick = _getMaxInitializedTick(currentTick);
            } else {
                // unsure if all ticks above the current tick were liquidated, but some were
                _maxInitializedTick = _getMaxInitializedTick(tick);
            }
        }

        // Transfer remaining collateral to vault or pay bad debt
        if (remainingCollateral_ >= 0) {
            if (uint256(remainingCollateral_) > _balanceLong) {
                // avoid underflow
                remainingCollateral_ = int256(_balanceLong);
            }
            _balanceVault += uint256(remainingCollateral_);
            unchecked {
                // underflow not possible thanks to the previous check
                _balanceLong -= uint256(remainingCollateral_);
            }
        } else {
            if (uint256(-remainingCollateral_) > _balanceVault) {
                // avoid underflow
                remainingCollateral_ = -int256(_balanceVault);
            }
            unchecked {
                // underflow not possible thanks to the previous check
                _balanceVault -= uint256(-remainingCollateral_);
            }
            _balanceLong += uint256(-remainingCollateral_);
        }
    }
}

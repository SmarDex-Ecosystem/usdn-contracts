// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { LibBitmap } from "solady/src/utils/LibBitmap.sol";
import { FixedPointMathLib } from "solady/src/utils/FixedPointMathLib.sol";

import { Position } from "src/interfaces/UsdnProtocol/IUsdnProtocol.sol";
import { UsdnProtocolVault } from "src/UsdnProtocol/UsdnProtocolVault.sol";
import { TickMath } from "src/libraries/TickMath.sol";
import { SignedMath } from "src/libraries/SignedMath.sol";

abstract contract UsdnProtocolLong is UsdnProtocolVault {
    using LibBitmap for LibBitmap.Bitmap;
    using SafeCast for uint256;
    using SafeCast for int256;
    using SignedMath for int256;

    function minTick() public view returns (int24 tick_) {
        tick_ = TickMath.minUsableTick(_tickSpacing);
    }

    function maxTick() public view returns (int24 tick_) {
        tick_ = TickMath.maxUsableTick(_tickSpacing);
    }

    function getLongPosition(int24 tick, uint256 index) public view returns (Position memory pos_) {
        pos_ = _longPositions[_tickHash(tick)][index];
    }

    function getLongPositionsLength(int24 tick) external view returns (uint256 len_) {
        len_ = _positionsInTick[_tickHash(tick)];
    }

    function getMinLiquidationPrice(uint128 price) public view returns (uint128 liquidationPrice_) {
        liquidationPrice_ = getLiquidationPrice(price, uint40(_minLeverage));
        int24 tick = getEffectiveTickForPrice(liquidationPrice_);
        liquidationPrice_ = getEffectivePriceForTick(tick + _tickSpacing);
    }

    function findMaxInitializedTick(int24 searchStart) public view returns (int24 tick_) {
        uint256 index = _tickBitmap.findLastSet(_tickToBitmapIndex(searchStart));
        if (index == LibBitmap.NOT_FOUND) {
            tick_ = minTick();
        } else {
            tick_ = _bitmapIndexToTick(index);
        }
    }

    function getLiquidationPrice(uint128 startPrice, uint40 leverage) public pure returns (uint128 price_) {
        price_ = startPrice - ((uint128(10) ** LEVERAGE_DECIMALS * startPrice) / leverage);
    }

    /// @dev This applies the liquidation penalty
    function getLeverageWithLiquidationPenalty(uint128 startPrice, uint128 liquidationPrice)
        public
        view
        returns (uint40 leverage_)
    {
        if (startPrice <= liquidationPrice) {
            // this situation is not allowed (newly open position must be solvent)
            revert UsdnProtocolInvalidLiquidationPrice(liquidationPrice, startPrice);
        }

        // From here, the following holds true: startPrice > liquidationPrice >= theoreticalLiquidationPrice

        // Apply liquidation penalty
        // theoretical liquidation price = 0.98 * desired liquidation price
        // TODO: check if unchecked math would be ok
        liquidationPrice =
            (liquidationPrice * (PERCENTAGE_DIVISOR - _liquidationPenalty) / PERCENTAGE_DIVISOR).toUint128();

        leverage_ = _getLeverage(startPrice, liquidationPrice);
    }

    function positionPnl(uint128 currentPrice, uint128 startPrice, uint128 amount, uint40 leverage)
        public
        pure
        returns (int256 pnl_)
    {
        int256 priceDiff = _toInt256(currentPrice).safeSub(_toInt256(startPrice));
        pnl_ = _toInt256(amount).safeMul(priceDiff).safeMul(_toInt256(leverage)).safeDiv(
            _toInt256(startPrice) * int256(10) ** LEVERAGE_DECIMALS
        );
    }

    function positionValue(uint128 currentPrice, uint128 startPrice, uint128 amount, uint40 leverage)
        public
        pure
        returns (int256 value_)
    {
        value_ = _toInt256(amount).safeAdd(positionPnl(currentPrice, startPrice, amount, leverage));
    }

    function getEffectiveTickForPrice(uint128 price) public view returns (int24 tick_) {
        if (price < TickMath.MIN_PRICE) {
            return minTick();
        }

        int24 tickSpacing = _tickSpacing;
        tick_ = TickMath.getTickAtPrice(
            // adjusted price with liquidation multiplier
            FixedPointMathLib.fullMulDiv(uint256(price), 10 ** LIQUIDATION_MULTIPLIER_DECIMALS, _liquidationMultiplier)
        );

        // round down to the next valid tick according to _tickSpacing (towards negative infinity)
        if (tick_ < 0) {
            // we round up the inverse number (positive) then invert it -> round towards negative infinity
            tick_ = -int24(int256(FixedPointMathLib.divUp(uint256(int256(-tick_)), uint256(int256(tickSpacing)))))
                * tickSpacing;
            // avoid invalid ticks
            int24 minUsableTick = minTick();
            if (tick_ < minUsableTick) {
                tick_ = minUsableTick;
            }
        } else {
            // rounding is desirable here
            // slither-disable-next-line divide-before-multiply
            tick_ = (tick_ / tickSpacing) * tickSpacing;
        }
    }

    function getEffectivePriceForTick(int24 tick) public view returns (uint128 price_) {
        // adjusted price with liquidation multiplier
        price_ = FixedPointMathLib.fullMulDiv(
            TickMath.getPriceAtTick(tick), _liquidationMultiplier, 10 ** LIQUIDATION_MULTIPLIER_DECIMALS
        ).toUint128();
    }

    /// @dev This does not take into account the liquidation penalty
    function _getLeverage(uint128 startPrice, uint128 liquidationPrice) internal pure returns (uint40 leverage_) {
        if (startPrice <= liquidationPrice) {
            // this situation is not allowed (newly open position must be solvent)
            // Also, calculation below would underflow
            revert UsdnProtocolInvalidLiquidationPrice(liquidationPrice, startPrice);
        }

        leverage_ = ((10 ** LEVERAGE_DECIMALS * uint256(startPrice)) / (startPrice - liquidationPrice)).toUint40();
    }

    function _maxLiquidationPriceWithSafetyMargin(uint128 price) internal view returns (uint128 maxLiquidationPrice_) {
        maxLiquidationPrice_ = uint128(price * (PERCENTAGE_DIVISOR - _safetyMargin) / PERCENTAGE_DIVISOR);
    }

    function _checkSafetyMargin(uint128 currentPrice, uint128 liquidationPrice) internal view {
        uint128 maxLiquidationPrice = _maxLiquidationPriceWithSafetyMargin(currentPrice);
        if (liquidationPrice >= maxLiquidationPrice) {
            revert UsdnProtocolLiquidationPriceSafetyMargin(liquidationPrice, maxLiquidationPrice);
        }
    }

    function _saveNewPosition(int24 tick, Position memory long) internal returns (uint256 index_) {
        bytes32 tickHash = _tickHash(tick);

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
            _tickBitmap.set(_tickToBitmapIndex(tick));
        }
        if (tick > _maxInitializedTick) {
            // keep track of max initialized tick
            _maxInitializedTick = tick;
        }
        tickArray.push(long);
    }

    function _removePosition(int24 tick, uint256 index, Position memory long) internal {
        bytes32 tickHash = _tickHash(tick);

        // Adjust state
        uint256 removeExpo = FixedPointMathLib.fullMulDiv(long.amount, long.leverage, 10 ** LEVERAGE_DECIMALS);
        _totalExpo -= removeExpo;
        _totalExpoByTick[tickHash] -= removeExpo;
        --_positionsInTick[tickHash];
        --_totalLongPositions;

        // Remove from tick array (set to zero to avoid shifting indices)
        Position[] storage tickArray = _longPositions[tickHash];
        delete tickArray[index];
        if (_positionsInTick[tickHash] == 0) {
            // we removed the last position in the tick
            _tickBitmap.unset(_tickToBitmapIndex(tick));
        }
    }

    /**
     * @dev Convert a signed tick to an unsigned index into the Bitmap
     * @param tick The tick to convert, a multiple of `tickSpacing`
     * @return index_ The index into the Bitmap
     */
    function _tickToBitmapIndex(int24 tick) internal view returns (uint256 index_) {
        int24 compactTick = tick / _tickSpacing;
        // shift into positive and cast to uint256
        index_ = uint256(int256(compactTick) - int256(type(int24).min));
    }

    /**
     * @dev Convert a Bitmap index to a signed tick
     * @param index The index into the Bitmap
     * @return tick_ The tick corresponding to the index, a multiple of `tickSpacing`
     */
    function _bitmapIndexToTick(uint256 index) internal view returns (int24 tick_) {
        // cast to int256 and shift into negative
        int24 compactTick = (int256(index) + int256(type(int24).min)).toInt24();
        tick_ = compactTick * _tickSpacing;
    }

    function _tickHash(int24 tick) internal view returns (bytes32) {
        return keccak256(abi.encodePacked(tick, _tickVersion[tick]));
    }

    function _liquidatePositions(uint256 currentPrice, uint16 iteration) internal returns (uint256 liquidated_) {
        // max iteration limit
        if (iteration > MAX_LIQUIDATION_ITERATION) {
            iteration = MAX_LIQUIDATION_ITERATION;
        }

        // TODO: !!! need to change when the liquidation multiplier is added!
        int24 currentTick = TickMath.getClosestTickAtPrice(uint256(currentPrice));
        int24 tick = _maxInitializedTick;

        uint256 i;
        do {
            uint256 index = _tickBitmap.findLastSet(_tickToBitmapIndex(tick));
            if (index == LibBitmap.NOT_FOUND) {
                // no populated ticks left
                break;
            }

            tick = _bitmapIndexToTick(index);
            if (tick < currentTick) {
                break;
            }

            // we have found a non-empty tick that needs to be liquidated
            bytes32 tickHash = _tickHash(tick);
            uint256 length = _positionsInTick[tickHash];

            unchecked {
                _totalExpo -= _totalExpoByTick[tickHash];

                _totalLongPositions -= length;
                liquidated_ += length;

                ++_tickVersion[tick];
                ++i;
            }
            _tickBitmap.unset(_tickToBitmapIndex(tick));
        } while (i < iteration);

        if (liquidated_ != 0) {
            if (tick < currentTick) {
                // all ticks above the current tick were liquidated
                _maxInitializedTick = findMaxInitializedTick(currentTick);
            } else {
                // unsure if all ticks above the current tick were liquidated, but some were
                _maxInitializedTick = findMaxInitializedTick(tick);
            }
        }
        // TODO transfer remaining collat to vault
    }
}

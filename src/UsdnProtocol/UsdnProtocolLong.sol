// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import { LibBitmap } from "solady/src/utils/LibBitmap.sol";
import { FixedPointMathLib } from "solady/src/utils/FixedPointMathLib.sol";

import { Position } from "src/interfaces/UsdnProtocol/IUsdnProtocol.sol";
import { UsdnProtocolVault } from "src/UsdnProtocol/UsdnProtocolVault.sol";
import { TickMath } from "src/libraries/TickMath.sol";

abstract contract UsdnProtocolLong is UsdnProtocolVault {
    using LibBitmap for LibBitmap.Bitmap;

    function getLongPosition(int24 tick, uint256 index) public view returns (Position memory pos_) {
        pos_ = _longPositions[_tickHash(tick)][index];
    }

    function getLongPositionsLength(int24 tick) external view returns (uint256 len_) {
        len_ = _positionsInTick[_tickHash(tick)];
    }

    function findMaxInitializedTick(int24 searchStart) public view returns (int24 tick_) {
        uint256 index = _tickBitmap.findLastSet(_tickToBitmapIndex(searchStart));
        if (index == LibBitmap.NOT_FOUND) {
            tick_ = TickMath.minUsableTick(_tickSpacing);
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
        liquidationPrice = uint128(liquidationPrice * (PERCENTAGE_DIVISOR - _liquidationPenalty) / PERCENTAGE_DIVISOR);

        leverage_ = _getLeverage(startPrice, liquidationPrice);
    }

    function positionPnl(uint128 currentPrice, uint128 startPrice, uint128 amount, uint40 leverage)
        public
        pure
        returns (int256 pnl_)
    {
        int256 priceDiff = int256(uint256(currentPrice)) - int256(uint256(startPrice));
        pnl_ = (int256(uint256(amount)) * priceDiff * int256(uint256(leverage)))
            / (int256(uint256(startPrice)) * int256(10) ** LEVERAGE_DECIMALS);
    }

    function positionValue(uint128 currentPrice, uint128 startPrice, uint128 amount, uint40 leverage)
        public
        pure
        returns (int256 value_)
    {
        value_ = int256(uint256(amount)) + positionPnl(currentPrice, startPrice, amount, leverage);
    }

    /// @dev This does not take into account the liquidation penalty
    function _getLeverage(uint128 startPrice, uint128 liquidationPrice) internal pure returns (uint40 leverage_) {
        if (startPrice <= liquidationPrice) {
            // this situation is not allowed (newly open position must be solvent)
            // Also, calculation below would underflow
            revert UsdnProtocolInvalidLiquidationPrice(liquidationPrice, startPrice);
        }

        leverage_ = uint40((10 ** LEVERAGE_DECIMALS * uint256(startPrice)) / (startPrice - liquidationPrice));
    }

    function _maxLiquidationPriceWithSafetyMargin(uint128 price) internal view returns (uint128 maxLiquidationPrice_) {
        maxLiquidationPrice_ = uint128(price * (PERCENTAGE_DIVISOR - _safetyMargin) / PERCENTAGE_DIVISOR);
    }

    function _checkSafetyMargin(uint128 currentPrice, uint128 liquidationPrice) internal view {
        uint128 maxLiquidationPrice = _maxLiquidationPriceWithSafetyMargin(currentPrice);
        if (liquidationPrice < maxLiquidationPrice) {
            revert UsdnProtocolLiquidationPriceSafetyMargin(liquidationPrice, maxLiquidationPrice);
        }
    }

    function _saveNewPosition(int24 tick, Position memory long) internal returns (uint256 index_) {
        bytes32 tickHash = _tickHash(tick);

        // Adjust state
        _balanceLong += long.amount;
        uint256 addExpo = (long.amount * long.leverage) / 10 ** LEVERAGE_DECIMALS;
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
        uint256 removeExpo = (long.amount * long.leverage) / 10 ** LEVERAGE_DECIMALS;
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

    function _getEffectiveTickForPrice(uint128 price) internal view returns (int24 tick_) {
        tick_ = TickMath.getTickAtPrice(uint256(price));
        // round down to the next valid tick according to _tickSpacing (towards negative infinity)
        if (tick_ < 0) {
            // we round up the inverse number (positive) then invert it -> round towards negative infinity
            tick_ = -int24(int256(FixedPointMathLib.divUp(uint256(int256(-tick_)), uint256(int256(_tickSpacing)))))
                * _tickSpacing;
            // avoid invalid ticks
            int24 minTick = TickMath.minUsableTick(_tickSpacing);
            if (tick_ < minTick) {
                tick_ = minTick;
            }
        } else {
            tick_ = (tick_ / _tickSpacing) * _tickSpacing;
        }
    }

    function _getEffectivePriceForTick(int24 tick) internal pure returns (uint128 price_) {
        price_ = uint128(TickMath.getPriceAtTick(tick));
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
        int24 compactTick = int24(int256(index) + int256(type(int24).min));
        tick_ = compactTick * _tickSpacing;
    }

    function _tickHash(int24 tick) internal view returns (bytes32) {
        return keccak256(abi.encodePacked(tick, _tickVersion[tick]));
    }
}

// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.20;

import { ABDKMathQuad } from "abdk-libraries-solidity/ABDKMathQuad.sol";

library TickMath {
    error InvalidTick();
    error InvalidPrice();

    // The minimum price we want to resolve is 1e-18, which equates to 1.001^-41_467
    // but due to precision loss we don't use the last tick
    int24 internal constant MIN_TICK = -41_466;

    // There is no technical bound on the maximum tick, but in practice we use the same as MIN_TICK
    int24 internal constant MAX_TICK = -MIN_TICK;

    // Min and max values
    bytes16 internal constant MIN_PRICE = 0x3fc327846f7283fb8881cd99fe0a732f;
    bytes16 internal constant MAX_PRICE = 0x403abb88b85546c596a0c256d0be628e;

    // Pre-computed value for log2(1.001)
    bytes16 internal constant LOG2_BASE = 0x3ff57a013faca6c6a8ba2fc9d3b9fd94;

    function maxUsableTick(int24 tickSpacing) internal pure returns (int24 tick) {
        unchecked {
            tick = (MAX_TICK / tickSpacing) * tickSpacing;
        }
    }

    function minUsableTick(int24 tickSpacing) internal pure returns (int24 tick) {
        unchecked {
            tick = (MIN_TICK / tickSpacing) * tickSpacing;
        }
    }

    function fromDecimal(int256 price, uint8 decimals) internal pure returns (bytes16 p) {
        p = ABDKMathQuad.div(ABDKMathQuad.fromInt(price), ABDKMathQuad.fromUInt(10 ** decimals));
    }

    function toDecimal(bytes16 value, uint8 decimals) internal pure returns (int256 p) {
        // rounded towards zero
        int256 p1 = ABDKMathQuad.toInt(ABDKMathQuad.mul(value, ABDKMathQuad.fromUInt(10 ** decimals)));

        int8 sign = ABDKMathQuad.sign(value);
        if (sign == 0) return 0;

        // rounded away from zero
        int256 p2 = sign < 0 ? p1 - 1 : p1 + 1;

        // check which is closest from t1 or t2
        bytes16 diff1 = ABDKMathQuad.abs(ABDKMathQuad.sub(value, fromDecimal(p1, decimals)));
        bytes16 diff2 = ABDKMathQuad.abs(ABDKMathQuad.sub(value, fromDecimal(p2, decimals)));
        p = diff1 < diff2 ? p1 : p2;
    }

    /**
     * @notice Gets the price at a given tick
     * @dev Calculates the price as 1.001^tick = 2^(tick * log_2(1.001))
     * @param tick The tick
     * @return price The price
     */
    function getPriceAtTick(int24 tick) internal pure returns (bytes16 price) {
        if (tick > MAX_TICK || tick < MIN_TICK) revert InvalidTick();
        price = ABDKMathQuad.pow_2(ABDKMathQuad.mul(LOG2_BASE, ABDKMathQuad.fromInt(int256(tick))));
    }

    /**
     * @notice Gets the tick corresponding to price, rounded down towards negative infinity.
     * @dev log2(price)/log2(1.001) gives the tick
     * @param price The price
     * @return tick The tick corresponding to the price
     */
    function getTickAtPrice(bytes16 price) internal pure returns (int24 tick) {
        if (ABDKMathQuad.cmp(price, MIN_PRICE) == -1 || ABDKMathQuad.cmp(price, MAX_PRICE) == 1) revert InvalidPrice();

        bytes16 t = ABDKMathQuad.div(ABDKMathQuad.log_2(price), LOG2_BASE);
        int8 sign = ABDKMathQuad.sign(t);
        if (sign == 0) return 0;

        // rounded towards zero
        int24 t1 = int24(ABDKMathQuad.toInt(t));

        if (sign < 0) {
            // if negative, check if it's exactly on a tick
            tick = ABDKMathQuad.eq(price, getPriceAtTick(t1)) ? t1 : t1 - 1;
        } else {
            tick = t1;
        }
    }

    /**
     * @notice Gets the tick closest to price
     * @dev log2(price)/log2(1.001) gives the tick
     * @param price The price
     * @return tick The closest tick to the price
     */
    function getClosestTickAtPrice(bytes16 price) internal pure returns (int24 tick) {
        if (ABDKMathQuad.cmp(price, MIN_PRICE) == -1 || ABDKMathQuad.cmp(price, MAX_PRICE) == 1) revert InvalidPrice();

        bytes16 t = ABDKMathQuad.div(ABDKMathQuad.log_2(price), LOG2_BASE);
        int8 sign = ABDKMathQuad.sign(t);
        if (sign == 0) return 0;

        // rounded towards zero
        int24 t1 = int24(ABDKMathQuad.toInt(t));

        // rounded away from zero
        int24 t2 = sign < 0 ? t1 - 1 : t1 + 1;

        // check which is closest from t1 or t2
        bytes16 diff1 = ABDKMathQuad.abs(ABDKMathQuad.sub(price, getPriceAtTick(t1)));
        bytes16 diff2 = ABDKMathQuad.abs(ABDKMathQuad.sub(price, getPriceAtTick(t2)));
        tick = diff1 < diff2 ? t1 : t2;
    }
}

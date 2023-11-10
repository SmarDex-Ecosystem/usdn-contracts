// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import { FixedPointMathLib } from "solady/src/utils/FixedPointMathLib.sol";

library TickMath {
    error InvalidTick();
    error InvalidPrice();

    // The minimum price we want to resolve is 1000 wei, which equates to 1.001^-34_556
    int24 internal constant MIN_TICK = -34_556;

    // The maximum tick is determined by what price foundry can handle in `assertApproxEqRel` for testing.
    int24 internal constant MAX_TICK = 93_532;

    // Min and max values
    uint256 internal constant MIN_PRICE = 1000;
    uint256 internal constant MAX_PRICE = 39_823_075_360_216_634_032_273_880_460_244_960_603_683_768_332_879_368_712_516;

    // Pre-computed value for ln(1.001)
    int256 internal constant LN_BASE = 999_500_333_083_533;

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

    /**
     * @notice Gets the price at a given tick
     * @dev Calculates the price as 1.001^tick = 2^(tick * log_2(1.001)) = e^(tick * ln(1.001))
     * @param tick The tick
     * @return price The price
     */
    function getPriceAtTick(int24 tick) internal pure returns (uint256 price) {
        if (tick > MAX_TICK || tick < MIN_TICK) revert InvalidTick();
        price = uint256(FixedPointMathLib.expWad(tick * LN_BASE));
    }

    /**
     * @notice Gets the tick corresponding to price, rounded down towards negative infinity.
     * @dev log2(price)/log2(1.001) = ln(price)/ln(1.001) gives the tick
     * @param price The price
     * @return tick The tick corresponding to the price
     */
    function getTickAtPrice(uint256 price) internal pure returns (int24 tick) {
        if (price < MIN_PRICE || price > MAX_PRICE) revert InvalidPrice();

        int256 ln = FixedPointMathLib.lnWad(int256(price));
        if (ln == 0) {
            return 0;
        } else if (ln < 0) {
            // we round up the positive number then invert it -> round towards negative infinity
            tick = -int24(int256(FixedPointMathLib.divUp(uint256(-ln), uint256(LN_BASE))));
            if (tick < MIN_TICK) {
                // avoid invalid ticks
                tick = tick + 1;
            }
        } else {
            // we round down the positive number -> round towards negative infinity
            tick = int24(ln / LN_BASE);
        }
    }

    /**
     * @notice Gets the tick closest to price
     * @dev log2(price)/log2(1.001) = ln(price)/ln(1.001) gives the tick
     * @param price The price
     * @return tick The closest tick to the price
     */
    function getClosestTickAtPrice(uint256 price) internal pure returns (int24 tick) {
        if (price < MIN_PRICE || price > MAX_PRICE) revert InvalidPrice();

        int256 ln = FixedPointMathLib.lnWad(int256(price));
        // rounded up and down
        int24 t1;
        int24 t2;
        if (ln == 0) {
            return 0;
        } else if (ln < 0) {
            // rounded towards zero
            t1 = int24(ln / LN_BASE);
            // rounded away from zero
            t2 = t1 - 1;
            if (t2 < MIN_TICK) {
                // avoid invalid ticks
                return t1;
            }
        } else {
            // rounded towards zero
            t1 = int24(ln / LN_BASE);
            // rounded away from zero
            t2 = t1 + 1;
            if (t2 > MAX_TICK) {
                // avoid invalid ticks
                return t1;
            }
        }

        // check which is closest from t1 or t2
        uint256 diff1 = FixedPointMathLib.abs(int256(price) - int256(getPriceAtTick(t1)));
        uint256 diff2 = FixedPointMathLib.abs(int256(price) - int256(getPriceAtTick(t2)));
        tick = diff1 < diff2 ? t1 : t2;
    }
}

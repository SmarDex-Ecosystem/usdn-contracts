// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import { FixedPointMathLib } from "solady/src/utils/FixedPointMathLib.sol";

/**
 * @title TickMath
 * @author @beeb
 * @notice Convert between prices and ticks, where each tick represents an increase in price of 0.1%. Ticks are
 * used instead of liquidation prices to limit the number of possible buckets where a position can land, and allows for
 * batched liquidations.
 * @dev The formula for calculating the price from a tick is: price = 1.001^(tick).
 * The formula for calculating the tick from a price is: tick = log_1.001(price)
 */
library TickMath {
    /// @dev Indicates that the provided tick spacing is invalid (zero).
    error InvalidTickSpacing();

    /// @dev Indicates that the provided tick is out of bounds.
    error InvalidTick();

    /// @dev Indicates that the provided price is out of bounds.
    error InvalidPrice();

    // The minimum price we want to resolve is 1000 wei, which equates to 1.001^-34_556
    int24 internal constant MIN_TICK = -34_556;

    // The maximum tick is determined by limits of the libraries used for math and testing.
    int24 internal constant MAX_TICK = 98_000;

    // Min and max representable values for the price
    uint256 internal constant MIN_PRICE = 1000;
    uint256 internal constant MAX_PRICE =
        3_464_120_361_320_951_603_222_457_022_263_209_963_088_421_212_476_539_374_818_919;

    // Pre-computed value for ln(1.001)
    int256 internal constant LN_BASE = 999_500_333_083_533;

    /**
     * @notice Get the largest usable tick, given a tick spacing.
     * @param tickSpacing only use ticks that are a multiple of this value
     * @return tick_ the largest tick that can be used
     */
    function maxUsableTick(int24 tickSpacing) internal pure returns (int24 tick_) {
        if (tickSpacing == 0) revert InvalidTickSpacing();
        unchecked {
            // we want to round, so divide before multiply is desired
            // slither-disable-next-line divide-before-multiply
            tick_ = (MAX_TICK / tickSpacing) * tickSpacing;
        }
    }

    /**
     * @notice Get the smallest usable tick, given a tick spacing.
     * @param tickSpacing only use ticks that are a multiple of this value
     * @return tick_ the smallest tick that can be used
     */
    function minUsableTick(int24 tickSpacing) internal pure returns (int24 tick_) {
        if (tickSpacing == 0) revert InvalidTickSpacing();
        unchecked {
            // we want to round, so divide before multiply is desired
            // slither-disable-next-line divide-before-multiply
            tick_ = (MIN_TICK / tickSpacing) * tickSpacing;
        }
    }

    /**
     * @notice Get the price at a given tick
     * @dev Calculates the price as 1.001^tick = e^(tick * ln(1.001))
     * @param tick the tick
     * @return price_ the corresponding price
     */
    function getPriceAtTick(int24 tick) internal pure returns (uint256 price_) {
        if (tick > MAX_TICK) revert InvalidTick();
        if (tick < MIN_TICK) revert InvalidTick();
        price_ = uint256(FixedPointMathLib.expWad(tick * LN_BASE));
    }

    /**
     * @notice Get the tick corresponding to a price, rounded down towards negative infinity.
     * @dev log_1.001(price) = ln(price)/ln(1.001) gives the tick
     * @param price the price
     * @return tick_ the largest tick which price is less than or equal to the given price
     */
    function getTickAtPrice(uint256 price) internal pure returns (int24 tick_) {
        if (price < MIN_PRICE) revert InvalidPrice();
        if (price > MAX_PRICE) revert InvalidPrice();

        int256 ln = FixedPointMathLib.lnWad(int256(price));
        if (ln == 0) {
            return 0;
        } else if (ln < 0) {
            // we round up the positive number then invert it -> round towards negative infinity
            tick_ = -int24(int256(FixedPointMathLib.divUp(uint256(-ln), uint256(LN_BASE))));
            if (tick_ < MIN_TICK) {
                // avoid invalid ticks
                tick_ = tick_ + 1;
            }
        } else {
            // we round down the positive number -> round towards negative infinity
            tick_ = int24(ln / LN_BASE);
        }
    }

    /**
     * @notice Get the tick closest to price
     * @dev log_1.001(price) = ln(price)/ln(1.001) gives the tick
     * @param price the price
     * @return tick_ the closest tick to the given price
     */
    function getClosestTickAtPrice(uint256 price) internal pure returns (int24 tick_) {
        if (price < MIN_PRICE) revert InvalidPrice();
        if (price > MAX_PRICE) revert InvalidPrice();

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
                // note: this condition never hits with the current MAX_TICK value, but we keep it for safety
                return t1;
            }
        }

        // check which is closest from t1 or t2
        uint256 diff1 = FixedPointMathLib.abs(int256(price) - int256(getPriceAtTick(t1)));
        uint256 diff2 = FixedPointMathLib.abs(int256(price) - int256(getPriceAtTick(t2)));
        tick_ = diff1 < diff2 ? t1 : t2;
    }
}

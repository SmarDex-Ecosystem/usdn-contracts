// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import { FixedPointMathLib } from "solady/src/utils/FixedPointMathLib.sol";

/**
 * @notice Converts between prices and ticks, where each tick represents an increase in price of 0.01%. Ticks are used
 * instead of liquidation prices to limit the number of possible buckets where a position can land, and allows for
 * batched liquidations.
 * @dev The formula for calculating the price from a tick is: `price = 1.0001^(tick)`.
 * The formula for calculating the tick from a price is: tick = `log_1.0001(price)`.
 */
library TickMath {
    /// @dev The provided tick spacing is invalid (zero).
    error TickMathInvalidTickSpacing();

    /// @dev The provided tick is out of bounds.
    error TickMathInvalidTick();

    /// @dev The provided price is out of bounds.
    error TickMathInvalidPrice();

    /// @dev The minimum price we want to resolve is 10_000 wei (1e-14 USD), which equates to `1.0001^-322378`.
    int24 public constant MIN_TICK = -322_378;

    /// @dev The maximum tick is determined by the limits of the libraries used for math and testing.
    int24 public constant MAX_TICK = 980_000;

    /// @dev The minimum representable values for the price.
    uint256 public constant MIN_PRICE = 10_000;

    /// @dev The maximum representable values for the price.
    uint256 public constant MAX_PRICE =
        3_620_189_675_065_328_806_679_850_654_316_367_931_456_599_175_372_999_068_724_197;

    /// @dev Pre-computed value for `ln(1.0001)`.
    int256 public constant LN_BASE = 99_995_000_333_308;

    /**
     * @notice Gets the largest usable tick, given a tick spacing.
     * @param tickSpacing Only uses ticks that are a multiple of this value.
     * @return tick_ The largest tick that can be used.
     */
    function maxUsableTick(int24 tickSpacing) external pure returns (int24 tick_) {
        if (tickSpacing == 0) {
            revert TickMathInvalidTickSpacing();
        }
        unchecked {
            // we want to round, so divide before multiply is desired
            // slither-disable-next-line divide-before-multiply
            tick_ = (MAX_TICK / tickSpacing) * tickSpacing;
        }
    }

    /**
     * @notice Gets the smallest usable tick, given a tick spacing.
     * @param tickSpacing Only uses ticks that are a multiple of this value.
     * @return tick_ The smallest tick that can be used.
     */
    function minUsableTick(int24 tickSpacing) external pure returns (int24 tick_) {
        if (tickSpacing == 0) {
            revert TickMathInvalidTickSpacing();
        }
        unchecked {
            // we want to round, so divide before multiply is desired
            // slither-disable-next-line divide-before-multiply
            tick_ = (MIN_TICK / tickSpacing) * tickSpacing;
        }
    }

    /**
     * @notice Gets the price at a given tick.
     * @dev Calculates the price as `1.0001^tick = e^(tick * ln(1.0001))`.
     * @param tick The tick.
     * @return price_ The corresponding price.
     */
    function getPriceAtTick(int24 tick) public pure returns (uint256 price_) {
        if (tick > MAX_TICK) {
            revert TickMathInvalidTick();
        }
        if (tick < MIN_TICK) {
            revert TickMathInvalidTick();
        }
        price_ = uint256(FixedPointMathLib.expWad(tick * LN_BASE));
    }

    /**
     * @notice Gets the tick corresponding to a price, rounded down towards negative infinity.
     * @dev `log_1.0001(price) = ln(price)/ln(1.0001)` gives the tick.
     * @param price The price.
     * @return tick_ The largest tick whose price is less than or equal to the given price.
     */
    function getTickAtPrice(uint256 price) external pure returns (int24 tick_) {
        if (price < MIN_PRICE) {
            revert TickMathInvalidPrice();
        }
        if (price > MAX_PRICE) {
            revert TickMathInvalidPrice();
        }

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
}

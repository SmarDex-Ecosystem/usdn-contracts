// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { FixedPointMathLib } from "solady/src/utils/FixedPointMathLib.sol";

import { TickMathFixture } from "test/unit/TickMath/utils/Fixtures.sol";

import { TickMath } from "src/libraries/TickMath.sol";

/// @custom:feature Test constants defined in the `TickMath` library
contract TestTickMathConstants is TickMathFixture {
    /**
     * @custom:given The `LN_BASE` constant
     * @custom:then The `LN_BASE` constant is equal to the natural log of 1.001
     */
    function test_lnBase() public {
        int256 base = 1.001 ether;
        assertEq(FixedPointMathLib.lnWad(base), TickMath.LN_BASE);
    }

    /**
     * @custom:given The `MIN_TICK` constant
     * @custom:and The `MIN_PRICE` constant
     * @custom:then The `MIN_PRICE` constant is equal to the price corresponding to the `MIN_TICK` constant
     * @custom:and The `MIN_TICK` constant is equal to the tick corresponding to the `MIN_PRICE` constant
     */
    function test_minPrice() public {
        uint256 minPrice = handler.getPriceAtTick(TickMath.MIN_TICK);
        assertEq(minPrice, TickMath.MIN_PRICE);
        int24 tick = handler.getClosestTickAtPrice(TickMath.MIN_PRICE);
        assertEq(tick, TickMath.MIN_TICK);
    }

    /**
     * @custom:given The `MAX_TICK` constant
     * @custom:and The `MAX_PRICE` constant
     * @custom:then The `MAX_PRICE` constant is equal to the price corresponding to the `MAX_TICK` constant
     * @custom:and The `MAX_TICK` constant is equal to the tick corresponding to the `MAX_PRICE` constant
     */
    function test_maxPrice() public {
        uint256 maxPrice = handler.getPriceAtTick(TickMath.MAX_TICK);
        assertEq(maxPrice, TickMath.MAX_PRICE);
        int24 tick = handler.getClosestTickAtPrice(TickMath.MAX_PRICE);
        assertEq(tick, TickMath.MAX_TICK);
    }
}

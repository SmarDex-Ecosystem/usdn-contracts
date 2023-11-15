// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { console2 } from "forge-std/Test.sol";

import { FixedPointMathLib } from "solady/src/utils/FixedPointMathLib.sol";

import { TickMathFixture } from "test/unit/TickMath/utils/Fixtures.sol";

import { TickMath } from "src/libraries/TickMath.sol";

/// Fuzzing tests for conversions between tick and price
contract TestTickMathFuzzing is TickMathFixture {
    function setUp() public override {
        super.setUp();
    }

    /**
     * Check that the conversion from tick to price and back to tick doesn't lose precision with
     * `getClosestTickAtPrice`. When using `getTickAtPrice` the tick is rounded down, so it is at most 1 tick off.
     */
    function testFuzz_conversion(int24 tick) public {
        tick = bound_int24(tick, TickMath.MIN_TICK, TickMath.MAX_TICK);
        uint256 price = handler.getPriceAtTick(tick);
        console2.log("corresponding price", price);
        // Conversion from price to tick can lose precision, so to check equality we need to use the precise method
        int24 tick2 = handler.getClosestTickAtPrice(price);
        // The imprecise method should be within 1 tick of the precise method
        int24 tick3 = handler.getTickAtPrice(price);
        assertEq(tick2, tick);
        assertApproxEqAbs(tick3, tick, 1);
    }

    /**
     * Conversion from price to tick loses precision due to the discretization. Here we assess that a back-and-forth
     * conversion doesn't give a result that is more than 1 tick off (i.e. 0.1% of the price).
     */
    function testFuzz_conversionReverse(uint256 price) public {
        price = bound(price, TickMath.MIN_PRICE, TickMath.MAX_PRICE);
        int24 tick = handler.getClosestTickAtPrice(price);
        console2.log("corresponding tick", tick);
        uint256 price2 = handler.getPriceAtTick(tick);
        console2.log("price", price2);
        assertApproxEqRel(price, price2, 0.001 ether); // within 0.1%
    }
}

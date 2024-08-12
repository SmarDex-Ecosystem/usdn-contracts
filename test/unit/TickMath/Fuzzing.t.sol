// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { console2 } from "forge-std/Test.sol";

import { TickMathFixture } from "./utils/Fixtures.sol";

import { TickMath } from "../../../src/libraries/TickMath.sol";

/// @custom:feature Fuzzing tests for conversion functions in `TickMath`
contract TestTickMathFuzzing is TickMathFixture {
    function setUp() public override {
        super.setUp();
    }

    /**
     * @custom:scenario Converting a tick to a price and back to a tick (fuzzed)
     * @custom:given A valid tick
     * @custom:when The price at the tick is retrieved
     * @custom:and The closest tick for the corresponding price is retrieved
     * @custom:and The rounded down tick for the corresponding price is retrieved
     * @custom:then The closest tick is equal to the original tick
     * @custom:and The rounded down tick is within 1 tick of the original tick
     * @param tick The tick to convert to a price and back to a tick
     */
    function testFuzz_conversion(int24 tick) public view {
        tick = bound_int24(tick, TickMath.MIN_TICK, TickMath.MAX_TICK);
        uint256 price = handler.getPriceAtTick(tick);
        console2.log("corresponding price", price);
        // Conversion from price to tick can lose precision, so to check equality we need to use the precise method
        int24 tick2 = handler.getClosestTickAtPrice(price);
        // The imprecise method should be within 1 tick of the precise method
        int24 tick3 = handler.getTickAtPrice(price);
        assertEq(tick2, tick, "closest tick vs original tick");
        assertApproxEqAbs(tick3, tick, 1, "rounded down tick vs original tick");
    }

    /**
     * @custom:scenario Converting a price to a tick and back to a price (fuzzed)
     * @custom:given A valid price
     * @custom:when The closest tick for the price is retrieved
     * @custom:and The price at the corresponding tick is retrieved
     * @custom:then The price is equal to the original price within 0.01%
     * @param price The price to convert to a tick and back to a price
     */
    function testFuzz_conversionReverse(uint256 price) public view {
        price = bound(price, TickMath.MIN_PRICE, TickMath.MAX_PRICE);
        int24 tick = handler.getClosestTickAtPrice(price);
        console2.log("corresponding tick", tick);
        uint256 price2 = handler.getPriceAtTick(tick);
        console2.log("price", price2);
        assertApproxEqRel(price, price2, 0.0001 ether); // within 0.01%
    }
}

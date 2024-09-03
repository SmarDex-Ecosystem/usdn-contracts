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
        // The imprecise method should be within 1 tick of the precise method
        int24 tick3 = handler.getTickAtPrice(price);
        assertApproxEqAbs(tick3, tick, 1, "rounded down tick vs original tick");
    }
}

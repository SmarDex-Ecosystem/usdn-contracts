// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { TickMathFixture } from "./utils/Fixtures.sol";

import { TickMath } from "../../../src/libraries/TickMath.sol";

/// @custom:feature Test helper and conversion functions in `TickMath`
contract TestTickMathConcrete is TickMathFixture {
    function setUp() public override {
        super.setUp();
    }

    /**
     * @custom:scenario Retrieving the min and max usable ticks for positive tick spacing
     * @custom:given A tick spacing of 10_000
     * @custom:when The min and max usable ticks are retrieved
     * @custom:then The min usable tick is -320_000 and the max usable tick is 980_000
     */
    function test_tickMinMax() public view {
        int24 tickSpacing = 10_000;
        assertEq(handler.minUsableTick(tickSpacing), -320_000, "minUsableTick");
        assertEq(handler.maxUsableTick(tickSpacing), 980_000, "maxUsableTick");
    }

    /**
     * @custom:scenario Retrieving the min and max usable ticks for negative tick spacing
     * @custom:given A tick spacing of -60
     * @custom:when The min and max usable ticks are retrieved
     * @custom:then The min usable tick is -322_320 and the max usable tick is 979_980
     */
    function test_tickMinMaxNegative() public view {
        int24 tickSpacing = -60; // should never happen but we're safe here
        assertEq(handler.minUsableTick(tickSpacing), -322_320, "minUsableTick");
        assertEq(handler.maxUsableTick(tickSpacing), 979_980, "maxUsableTick");
    }

    /**
     * @custom:scenario Converting a tick to a price (some values, rest is fuzzed)
     * @custom:given A tick of -100, 0 or 100
     * @custom:when The price at the tick is retrieved
     * @custom:then The price is 990_050_328_741_209_514, 1.0001 ether +- 1 wei, or 1_010_049_662_092_876_534
     */
    function test_tickToPrice() public view {
        // Exact value according to WolframAlpha: 990_050_328_741_209_481
        assertEq(handler.getPriceAtTick(-100), 990_050_328_741_209_514, "price at tick -100");
        assertEq(handler.getPriceAtTick(0), 1 ether, "price at tick 0");
        assertApproxEqAbs(handler.getPriceAtTick(1), 1.0001 ether, 1, "price at tick 1"); // We are one wei off here
        // Exact value according to WolframAlpha: 1_010_049_662_092_876_569
        assertEq(handler.getPriceAtTick(100), 1_010_049_662_092_876_534, "price at tick 100");
    }

    /**
     * @custom:scenario An invalid ticks is provided to `getPriceAtTick`
     * @custom:given A tick of MIN_TICK - 1 or MAX_TICK + 1
     * @custom:when The price at the tick is retrieved
     * @custom:then The call reverts with `TickMathInvalidTick()`
     */
    function test_RevertWhen_tickIsOutOfBounds() public {
        vm.expectRevert(TickMath.TickMathInvalidTick.selector);
        handler.getPriceAtTick(TickMath.MIN_TICK - 1);
        vm.expectRevert(TickMath.TickMathInvalidTick.selector);
        handler.getPriceAtTick(TickMath.MAX_TICK + 1);
    }

    /**
     * @custom:scenario An invalid price is provided to `getTickAtPrice`
     * @custom:given A price of MIN_PRICE - 1 or MAX_PRICE + 1
     * @custom:when The tick for the price is retrieved with `getTickAtPrice`
     * @custom:then The call reverts with `TickMathInvalidPrice()`
     */
    function test_RevertWhen_priceIsOutOfBounds() public {
        vm.expectRevert(TickMath.TickMathInvalidPrice.selector);
        handler.getTickAtPrice(TickMath.MIN_PRICE - 1);
        vm.expectRevert(TickMath.TickMathInvalidPrice.selector);
        handler.getTickAtPrice(TickMath.MAX_PRICE + 1);
    }

    /**
     * @custom:scenario An invalid tick spacing is provided
     * @custom:given A tick spacing of 0
     * @custom:when The min or max usable tick is retrieved
     * @custom:then The call reverts with `TickMathInvalidTickSpacing()`
     */
    function test_RevertWhen_tickSpacingIsZero() public {
        vm.expectRevert(TickMath.TickMathInvalidTickSpacing.selector);
        handler.maxUsableTick(0);
        vm.expectRevert(TickMath.TickMathInvalidTickSpacing.selector);
        handler.minUsableTick(0);
    }

    /**
     * @custom:scenario Checking that the tick corresponding to the input price could have been tick + 1 for low prices
     * @custom:given A price below 1.025 gwei
     * @custom:when The rounded down tick for the corresponding price is retrieved
     * @custom:and The corresponding price for the tick is retrieved
     * @custom:then The corresponding price should be lower than the input price
     * @custom:and The price for tick + 1 should be equal to the input price
     */
    function test_getTickAtPriceWithNextTickWithEqualInputPrice() public view {
        uint128 price = 21_063;
        assertLt(price, 1.025 gwei, "price should be in the valid range");
        int24 tick = handler.getTickAtPrice(price);
        assertLt(handler.getPriceAtTick(tick), price, "tick price should be lower than the input price");
        assertEq(handler.getPriceAtTick(tick + 1), price, "next tick price should be equal input price");
    }
}

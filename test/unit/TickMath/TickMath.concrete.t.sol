// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { FixedPointMathLib } from "solady/src/utils/FixedPointMathLib.sol";

import { TickMathFixture } from "test/unit/TickMath/utils/Fixtures.sol";

import { TickMath } from "src/libraries/TickMath.sol";

/// @custom:feature Test helper and conversion functions in `TickMath`
contract TestTickMathConcrete is TickMathFixture {
    function setUp() public override {
        super.setUp();
    }

    /**
     * @custom:scenario Retrieving the min and max usable ticks for positive tick spacing
     * @custom:given A tick spacing of 10_000
     * @custom:when The min and max usable ticks are retrieved
     * @custom:then The min usable tick is -30_000 and the max usable tick is 90_000
     */
    function test_tickMinMax() public {
        int24 tickSpacing = 10_000;
        assertEq(handler.minUsableTick(tickSpacing), -30_000);
        assertEq(handler.maxUsableTick(tickSpacing), 90_000);
    }

    /**
     * @custom:scenario Retrieving the min and max usable ticks for negative tick spacing
     * @custom:given A tick spacing of -60
     * @custom:when The min and max usable ticks are retrieved
     * @custom:then The min usable tick is -34_500 and the max usable tick is 97_980
     */
    function test_tickMinMaxNegative() public {
        int24 tickSpacing = -60; // should never happen but we're safe here
        assertEq(handler.minUsableTick(tickSpacing), -34_500);
        assertEq(handler.maxUsableTick(tickSpacing), 97_980);
    }

    /**
     * @custom:scenario Converting a tick to a price (some values, rest is fuzzed)
     * @custom:given A tick of -100, 0 or 100
     * @custom:when The price at the tick is retrieved
     * @custom:then The price is 904_882_630_897_776_127, 1.001 ether +- 1 wei, or 1_105_115_697_720_767_949
     */
    function test_tickToPrice() public {
        assertEq(handler.getPriceAtTick(-100), 904_882_630_897_776_127); // Wolfram: 904_882_630_897_776_112
        assertEq(handler.getPriceAtTick(0), 1 ether);
        assertApproxEqAbs(handler.getPriceAtTick(1), 1.001 ether, 1); // We are one wei off here
        assertEq(handler.getPriceAtTick(100), 1_105_115_697_720_767_949); // Wolfram: 1_105_115_697_720_767_968
    }

    /**
     * @custom:scenario Converting a price to a tick (some values, rest is fuzzed)
     * @custom:given A price of 904_882_630_897_776_112, 1 ether or 1.001 ether
     * @custom:when The closest tick for the price is retrieved
     * @custom:then The closest tick is -100, 0 or 1
     */
    function test_priceToTick() public {
        assertEq(handler.getClosestTickAtPrice(904_882_630_897_776_112), -100);
        assertEq(handler.getClosestTickAtPrice(1 ether), 0);
        assertEq(handler.getClosestTickAtPrice(1.001 ether), 1);
    }

    /**
     * @custom:scenario An invalid ticks is provided to `getPriceAtTick`
     * @custom:given A tick of -34_557 or 98_001
     * @custom:when The price at the tick is retrieved
     * @custom:then The call reverts with `TickMathInvalidTick()`
     */
    function test_RevertWhen_tickIsOutOfBounds() public {
        vm.expectRevert(TickMath.TickMathInvalidTick.selector);
        handler.getPriceAtTick(-34_557);
        vm.expectRevert(TickMath.TickMathInvalidTick.selector);
        handler.getPriceAtTick(98_001);
    }

    /**
     * @custom:scenario An invalid price is provided to `getTickAtPrice`
     * @custom:given A price of MIN_PRICE - 1 or MAX_PRICE + 1
     * @custom:when The tick for the price is retrieved with `getTickAtPrice`
     * @custom:then The call reverts with `TickMathInvalidPrice()`
     */
    function test_RevertWhen_priceIsOutOfBounds() public {
        vm.expectRevert(TickMath.TickMathInvalidPrice.selector);
        handler.getTickAtPrice(999);
        vm.expectRevert(TickMath.TickMathInvalidPrice.selector);
        handler.getTickAtPrice(3_464_120_361_320_951_603_222_457_022_263_209_963_088_421_212_476_539_374_818_920);
    }

    /**
     * @custom:scenario An invalid price is provided to `getClosestTickAtPrice`
     * @custom:given A price of MIN_PRICE - 1 or MAX_PRICE + 1
     * @custom:when The tick for the price is retrieved with `getClosestTickAtPrice`
     * @custom:then The call reverts with `TickMathInvalidPrice()`
     */
    function test_RevertWhen_priceIsOutOfBoundsClosest() public {
        vm.expectRevert(TickMath.TickMathInvalidPrice.selector);
        handler.getClosestTickAtPrice(999);
        vm.expectRevert(TickMath.TickMathInvalidPrice.selector);
        handler.getClosestTickAtPrice(3_464_120_361_320_951_603_222_457_022_263_209_963_088_421_212_476_539_374_818_920);
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
}

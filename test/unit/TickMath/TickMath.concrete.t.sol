// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { console2 } from "forge-std/Test.sol";

import { FixedPointMathLib } from "solady/src/utils/FixedPointMathLib.sol";

import { TickMathFixture } from "test/unit/TickMath/utils/Fixtures.sol";

import { TickMath } from "src/libraries/TickMath.sol";

/// Deterministic tests, general conversions
contract TestTickMathConcrete is TickMathFixture {
    function setUp() public override {
        super.setUp();
    }

    /// Check that the min and max usable tick takes `tickSpacing` into account
    function test_tickMinMax() public {
        int24 tickSpacing = 10_000;
        assertEq(handler.minUsableTick(tickSpacing), -30_000);
        assertEq(handler.maxUsableTick(tickSpacing), 90_000);

        tickSpacing = -60; // should never happen but we're safe here
        assertEq(handler.minUsableTick(tickSpacing), -34_500);
        assertEq(handler.maxUsableTick(tickSpacing), 97_980);
    }

    /// Check the conversion from tick to price for some values (fuzzing takes care of the rest).
    function test_tickToPrice() public {
        assertEq(handler.getPriceAtTick(-100), 904_882_630_897_776_127); // Wolfram: 904_882_630_897_776_112
        assertEq(handler.getPriceAtTick(0), 1 ether);
        assertApproxEqAbs(handler.getPriceAtTick(1), 1.001 ether, 1); // We are one wei off here
        assertEq(handler.getPriceAtTick(100), 1_105_115_697_720_767_949); // Wolfram: 1_105_115_697_720_767_968
    }

    /// Check the conversion from price to tick for some values (fuzzing takes care of the rest).
    function test_priceToTick() public {
        assertEq(handler.getClosestTickAtPrice(904_882_630_897_776_112), -100);
        assertEq(handler.getClosestTickAtPrice(1 ether), 0);
        assertEq(handler.getClosestTickAtPrice(1.001 ether), 1);
    }

    /// Check that the `getPriceAtTick` function reverts when the tick is out of bounds.
    function test_RevertWhen_tickIsOutOfBounds() public {
        vm.expectRevert(TickMath.InvalidTick.selector);
        handler.getPriceAtTick(-34_557);
        vm.expectRevert(TickMath.InvalidTick.selector);
        handler.getPriceAtTick(98_001);
    }

    /// Check that the `getTickAtPrice` and `getClosestTickAtPrice` functions revert when the price is out of bounds.
    function test_RevertWhen_priceIsOutOfBounds() public {
        vm.expectRevert(TickMath.InvalidPrice.selector);
        handler.getTickAtPrice(999);
        vm.expectRevert(TickMath.InvalidPrice.selector);
        handler.getTickAtPrice(3_464_120_361_320_951_603_222_457_022_263_209_963_088_421_212_476_539_374_818_920);
        vm.expectRevert(TickMath.InvalidPrice.selector);
        handler.getClosestTickAtPrice(0);
        vm.expectRevert(TickMath.InvalidPrice.selector);
        handler.getClosestTickAtPrice(3_464_120_361_320_951_603_222_457_022_263_209_963_088_421_212_476_539_374_818_920);
    }

    /// Check that the maxUsableTick and minUsableTick functions revert when the tickSpacing is zero.
    function test_RevertWhen_tickSpacingIsZero() public {
        vm.expectRevert();
        handler.maxUsableTick(0);
        vm.expectRevert();
        handler.minUsableTick(0);
    }
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { console2 } from "forge-std/Test.sol";

import { FixedPointMathLib } from "solady/src/utils/FixedPointMathLib.sol";

import { TickMathFixture } from "test/utils/Fixtures.sol";
import { TickMathHandler } from "test/handlers/TickMathHandler.sol";

import { TickMath } from "src/libraries/TickMath.sol";

/**
 * @dev Tests for the TickMath library.
 *
 * The tests cover the values of the library constants, the conversion between ticks and prices, and the fuzzing of the
 * conversion functions.
 *
 * The fuzzing tests cover the full range of possible inputs for the conversion functions.
 */
contract TestTickMath is TickMathFixture {
    TickMathHandler handler;

    function setUp() public {
        handler = new TickMathHandler();
    }

    function test_lnBase() public {
        int256 base = 1.001 ether;
        assertEq(FixedPointMathLib.lnWad(base), TickMath.LN_BASE);
    }

    function test_minPrice() public {
        uint256 minPrice = TickMath.getPriceAtTick(TickMath.MIN_TICK);
        assertEq(minPrice, TickMath.MIN_PRICE);
        int24 tick = TickMath.getClosestTickAtPrice(TickMath.MIN_PRICE);
        assertEq(tick, TickMath.MIN_TICK);
    }

    function test_maxPrice() public {
        uint256 maxPrice = TickMath.getPriceAtTick(TickMath.MAX_TICK);
        assertEq(maxPrice, TickMath.MAX_PRICE);
        int24 tick = TickMath.getClosestTickAtPrice(TickMath.MAX_PRICE);
        assertEq(tick, TickMath.MAX_TICK);
    }

    function test_tickMinMax() public {
        int24 tickSpacing = 10_000;
        assertEq(TickMath.minUsableTick(tickSpacing), -30_000);
        assertEq(TickMath.maxUsableTick(tickSpacing), 90_000);

        tickSpacing = -60; // should never happen but we're safe here
        assertEq(TickMath.minUsableTick(tickSpacing), -34_500);
        assertEq(TickMath.maxUsableTick(tickSpacing), 97_980);
    }

    function test_tickToPrice() public {
        assertEq(handler.getPriceAtTick(-100), 904_882_630_897_776_127); // Wolfram: 904_882_630_897_776_112
        assertEq(handler.getPriceAtTick(0), 1 ether);
        assertApproxEqAbs(handler.getPriceAtTick(1), 1.001 ether, 1); // We are one wei off here
        assertEq(handler.getPriceAtTick(100), 1_105_115_697_720_767_949); // Wolfram: 1_105_115_697_720_767_968
    }

    function test_priceToTick() public {
        assertEq(handler.getClosestTickAtPrice(904_882_630_897_776_112), -100);
        assertEq(handler.getClosestTickAtPrice(1 ether), 0);
        assertEq(handler.getClosestTickAtPrice(1.001 ether), 1);
    }

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

    /// Conversion from price to tick can lose precision, so we use `getClosestTickAtPrice` and assert approximately
    function testFuzz_conversionReverse(uint256 price) public {
        price = bound(price, TickMath.MIN_PRICE, TickMath.MAX_PRICE);
        int24 tick = handler.getClosestTickAtPrice(price);
        console2.log("corresponding tick", tick);
        uint256 price2 = handler.getPriceAtTick(tick);
        console2.log("price", price2);
        assertApproxEqRel(price, price2, 0.001 ether); // within 0.1%
    }

    function testFuzz_conversionImprecise(uint256 price) public {
        price = _bound(price, TickMath.MIN_PRICE, TickMath.MAX_PRICE);
        int24 tick = handler.getTickAtPrice(price); // rounded down
        uint256 price2 = handler.getPriceAtTick(tick); // corresponding price (rounded down)
        int24 tick2 = handler.getTickAtPrice(price2); // convert back
        uint256 price3 = handler.getPriceAtTick(tick2); // to compare
        assertApproxEqRel(price2, price3, 0.002 ether); // within 0.2%
        assertLe(price2, price); // price2 <= price (since tick is rounded down)
    }
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { console2 } from "forge-std/Test.sol";

import { FixedPointMathLib } from "solady/src/utils/FixedPointMathLib.sol";

import { TickMathFixture } from "test/unit/TickMath/utils/Fixtures.sol";

import { TickMath } from "src/libraries/TickMath.sol";

/// Test constants defined in the library
contract TestTickMathConstants is TickMathFixture {
    /// Check that the natural log of 1.001 is the correct value
    function test_lnBase() public {
        int256 base = 1.001 ether;
        assertEq(FixedPointMathLib.lnWad(base), TickMath.LN_BASE);
    }

    /// Check that the `MIN_TICK` corresponds to the `MIN_PRICE` and vice-versa
    function test_minPrice() public {
        uint256 minPrice = handler.getPriceAtTick(TickMath.MIN_TICK);
        assertEq(minPrice, TickMath.MIN_PRICE);
        int24 tick = handler.getClosestTickAtPrice(TickMath.MIN_PRICE);
        assertEq(tick, TickMath.MIN_TICK);
    }

    /// Check that the `MAX_TICK` corresponds to the `MAX_PRICE` and vice-versa
    function test_maxPrice() public {
        uint256 maxPrice = handler.getPriceAtTick(TickMath.MAX_TICK);
        assertEq(maxPrice, TickMath.MAX_PRICE);
        int24 tick = handler.getClosestTickAtPrice(TickMath.MAX_PRICE);
        assertEq(tick, TickMath.MAX_TICK);
    }
}

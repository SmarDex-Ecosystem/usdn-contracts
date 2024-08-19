// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { UsdnProtocolBaseFixture } from "../utils/Fixtures.sol";

import { HugeUint } from "../../../../src/libraries/HugeUint.sol";

/// @custom:feature Test the _getTickFromDesiredLiqPrice internal function of the long layer
contract TestUsdnProtocolLongGetTickFromDesiredLiqPrice is UsdnProtocolBaseFixture {
    function setUp() public {
        super._setUp(DEFAULT_PARAMS);
    }

    function test_getTickFromLiqPrice_NoPenaltyNoSpacing() public view {
        // behaves like `TickMath.getTickAtPrice` without funding or penalty and tick spacing = 1
        uint24 penalty = 0;
        int24 tickSpacing = 1;
        uint128 desiredLiqPrice = 1 ether;
        (int24 tick, uint128 liqPrice) =
            protocol.i_getTickFromDesiredLiqPrice(desiredLiqPrice, 0, 0, HugeUint.wrap(0), tickSpacing, penalty);
        assertEq(tick, 0, "tick 0");
        assertEq(liqPrice, desiredLiqPrice, "price 1");

        desiredLiqPrice = 1000 ether;
        (tick, liqPrice) =
            protocol.i_getTickFromDesiredLiqPrice(desiredLiqPrice, 0, 0, HugeUint.wrap(0), tickSpacing, penalty);
        assertEq(tick, 69_081, "tick 69081");
        // not identical to desired liq price because
        // of rounding down in the price->tick conversion
        assertApproxEqRel(liqPrice, desiredLiqPrice, 0.0001 ether, "price 1000");
        assertLe(liqPrice, desiredLiqPrice, "liq price <= 1000");

        // negative tick
        desiredLiqPrice = 0.99 ether;
        (tick, liqPrice) =
            protocol.i_getTickFromDesiredLiqPrice(desiredLiqPrice, 0, 0, HugeUint.wrap(0), tickSpacing, penalty);
        assertEq(tick, -101, "tick -101");
        assertApproxEqRel(liqPrice, desiredLiqPrice, 0.0001 ether, "price 0.99");
        assertLe(liqPrice, desiredLiqPrice, "liq price <= 0.99");
    }

    function test_getTickFromLiqPrice_NoPenaltySpacing100() public view {
        // with tickSpacing = 100 but no penalty
        uint24 penalty = 0;
        int24 tickSpacing = 100;
        uint128 desiredLiqPrice = 1000 ether;
        (int24 tick, uint128 liqPrice) =
            protocol.i_getTickFromDesiredLiqPrice(desiredLiqPrice, 0, 0, HugeUint.wrap(0), tickSpacing, penalty);
        assertEq(tick, 69_000, "tick 69000");
        // not identical to desired liq price because
        // of rounding down in the price->tick conversion
        assertApproxEqRel(liqPrice, desiredLiqPrice, 0.01 ether, "price 1000");
        assertLe(liqPrice, desiredLiqPrice, "liq price <= 1000");

        // negative tick
        desiredLiqPrice = 0.99 ether;
        (tick, liqPrice) =
            protocol.i_getTickFromDesiredLiqPrice(desiredLiqPrice, 0, 0, HugeUint.wrap(0), tickSpacing, penalty);
        assertEq(tick, -200, "tick -200");
        assertApproxEqRel(liqPrice, desiredLiqPrice, 0.01 ether, "price 0.99");
        assertLe(liqPrice, desiredLiqPrice, "liq price <= 0.99");
    }

    function test_getTickFromLiqPrice_PenaltyNoSpacing() public view {
        uint24 penalty = 100;
        int24 tickSpacing = 1;
        uint128 desiredLiqPrice = 1000 ether;
        (int24 tick, uint128 liqPrice) =
            protocol.i_getTickFromDesiredLiqPrice(desiredLiqPrice, 0, 0, HugeUint.wrap(0), tickSpacing, penalty);
        assertEq(tick, 69_181, "tick 69181");
        // not identical to desired liq price because
        // of rounding down in the price->tick conversion
        assertApproxEqRel(liqPrice, desiredLiqPrice, 0.0001 ether, "price 1000");
        assertLe(liqPrice, desiredLiqPrice, "liq price <= 1000");

        // negative tick
        desiredLiqPrice = 0.99 ether;
        (tick, liqPrice) =
            protocol.i_getTickFromDesiredLiqPrice(desiredLiqPrice, 0, 0, HugeUint.wrap(0), tickSpacing, penalty);
        assertEq(tick, -1, "tick -1");
        assertApproxEqRel(liqPrice, desiredLiqPrice, 0.0001 ether, "price 0.99");
        assertLe(liqPrice, desiredLiqPrice, "liq price <= 0.99");
    }

    function test_getTickFromLiqPrice_PenaltySpacing100() public view {
        uint24 penalty = 100;
        int24 tickSpacing = 100;
        uint128 desiredLiqPrice = 1000 ether;
        (int24 tick, uint128 liqPrice) =
            protocol.i_getTickFromDesiredLiqPrice(desiredLiqPrice, 0, 0, HugeUint.wrap(0), tickSpacing, penalty);
        assertEq(tick, 69_100, "tick 69100");
        // not identical to desired liq price because
        // of rounding down in the price->tick conversion
        assertApproxEqRel(liqPrice, desiredLiqPrice, 0.01 ether, "price 1000");
        assertLe(liqPrice, desiredLiqPrice, "liq price <= 1000");

        // negative tick
        desiredLiqPrice = 0.99 ether;
        (tick, liqPrice) =
            protocol.i_getTickFromDesiredLiqPrice(desiredLiqPrice, 0, 0, HugeUint.wrap(0), tickSpacing, penalty);
        assertEq(tick, -100, "tick -100");
        assertApproxEqRel(liqPrice, desiredLiqPrice, 0.01 ether, "price 0.99");
        assertLe(liqPrice, desiredLiqPrice, "liq price <= 0.99");
    }

    function test_getTickFromLiqPrice_Penalty15Spacing100() public view {
        uint24 penalty = 15;
        int24 tickSpacing = 100;
        uint128 desiredLiqPrice = 1000 ether;
        (int24 tick, uint128 liqPrice) =
            protocol.i_getTickFromDesiredLiqPrice(desiredLiqPrice, 0, 0, HugeUint.wrap(0), tickSpacing, penalty);
        assertEq(tick, 69_000, "tick 69000");
        // not identical to desired liq price because
        // of rounding down in the price->tick conversion
        assertApproxEqRel(liqPrice, desiredLiqPrice, 0.01 ether, "price 1000");
        assertLe(liqPrice, desiredLiqPrice, "liq price <= 1000");

        // negative tick
        desiredLiqPrice = 0.99 ether;
        (tick, liqPrice) =
            protocol.i_getTickFromDesiredLiqPrice(desiredLiqPrice, 0, 0, HugeUint.wrap(0), tickSpacing, penalty);
        assertEq(tick, -100, "tick -200");
        assertApproxEqRel(liqPrice, desiredLiqPrice, 0.01 ether, "price 0.99");
        assertLe(liqPrice, desiredLiqPrice, "liq price <= 0.99");
    }
}

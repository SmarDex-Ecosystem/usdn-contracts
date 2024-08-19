// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { UsdnProtocolBaseFixture } from "../utils/Fixtures.sol";

import { UsdnProtocolConstantsLibrary as Constants } from
    "../../../../src/UsdnProtocol/libraries/UsdnProtocolConstantsLibrary.sol";
import { HugeUint } from "../../../../src/libraries/HugeUint.sol";
import { TickMath } from "../../../../src/libraries/TickMath.sol";

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

    function testFuzz_getTickFromLiqPrice(uint24 penalty, int24 tickSpacing, uint128 desiredLiqPrice) public view {
        penalty = uint24(bound(uint256(penalty), 0, Constants.MAX_LIQUIDATION_PENALTY));
        tickSpacing = int24(bound(tickSpacing, 1, 1000));
        desiredLiqPrice = uint128(bound(desiredLiqPrice, TickMath.MIN_PRICE, type(uint128).max));
        (int24 tick, uint128 liqPrice) =
            protocol.i_getTickFromDesiredLiqPrice(desiredLiqPrice, 0, 0, HugeUint.wrap(0), tickSpacing, penalty);
        assertEq(tick % tickSpacing, 0, "tick is multiple of tickSpacing");
        // for most cases, the final liq price will be less than or equal to the desired liq price
        // exception if the tick is close to the MIN_TICK, in which case that's not necessarily true (because the
        // min usable tick is effectively then `minUsableTick + penalty`)
        // we set the min tick bound for this check to be minUsableTick + tickSpacing + penalty (due to rounding)
        if (tick >= TickMath.minUsableTick(tickSpacing) + tickSpacing + int24(penalty)) {
            assertLe(liqPrice, desiredLiqPrice, "liq price <= desired");
        }
        // for most cases, the next tick would yield a liquidation price greater than the desired liq price
        // in some cases, due to rounding, the next tick would actually yield exactly the desired liq price and would
        // be a slightly better fit, but we always err towards the side of caution (do not impose a risk greater than
        // the user intended)
        assertGe(
            TickMath.getPriceAtTick(tick + tickSpacing - int24(penalty)), desiredLiqPrice, "next tick price >= desired"
        );
    }
}

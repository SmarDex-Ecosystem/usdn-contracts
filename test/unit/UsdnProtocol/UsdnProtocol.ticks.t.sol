// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { FixedPointMathLib } from "solady/src/utils/FixedPointMathLib.sol";

import { UsdnProtocolBaseFixture } from "test/unit/UsdnProtocol/utils/Fixtures.sol";

import { TickMath } from "src/libraries/TickMath.sol";

contract TestUsdnProtocolTicks is UsdnProtocolBaseFixture {
    function setUp() public override {
        super.setUp();
    }

    function testFuzz_liqPrice(uint128 price) public {
        price = uint128(bound(uint256(price), TickMath.MIN_PRICE, type(uint128).max));
        int24 closestTickDown = TickMath.getTickAtPrice(price);
        int24 tick = protocol.getEffectiveTickForPrice(price); // next valid tick towards infinity
        // make sure we rounded down (except at low end)
        // e.g. if desired price is 1000, the closest tick down is -34_556, but the min usable tick is -34_550
        closestTickDown = int24(
            FixedPointMathLib.max(int256(closestTickDown), int256(TickMath.minUsableTick(protocol.tickSpacing())))
        );
        assertLe(tick, closestTickDown);
        // make sure the effective liquidation price is always <= the desired liquidation price (except at low end)
        // e.g. if desired price is 1000, the lowest usable tick gives a price of 1006, so the effective price is 1006
        price = uint128(
            FixedPointMathLib.max(
                uint256(price), uint256(TickMath.getPriceAtTick(TickMath.minUsableTick(protocol.tickSpacing())))
            )
        );
        uint128 effLiqPrice = protocol.getEffectivePriceForTick(tick);
        assertLe(effLiqPrice, price);
    }
}

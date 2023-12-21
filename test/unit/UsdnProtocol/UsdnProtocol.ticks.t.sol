// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { UsdnProtocolBaseFixture } from "test/unit/UsdnProtocol/utils/Fixtures.sol";

import { TickMath } from "src/libraries/TickMath.sol";

contract TestUsdnProtocolTicks is UsdnProtocolBaseFixture {
    function setUp() public override {
        super.setUp();
    }

    function testFuzz_liqPrice(uint128 price) public {
        price = uint128(bound(uint256(price), TickMath.MIN_PRICE, type(uint128).max));
        int24 closestTick = TickMath.getTickAtPrice(price);
        int24 tick = protocol.getEffectiveTickForPrice(price); // next valid tick towards infinity
        // make sure we rounded down
        assertLe(tick, closestTick);
        // make sure the effective liquidation price is always <= the desired liquidation price
        uint128 effLiqPrice = protocol.getEffectivePriceForTick(tick);
        assertLe(effLiqPrice, price);
    }
}

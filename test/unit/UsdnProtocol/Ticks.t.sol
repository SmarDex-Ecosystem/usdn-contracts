// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { FixedPointMathLib } from "solady/src/utils/FixedPointMathLib.sol";

import { UsdnProtocolBaseFixture } from "./utils/Fixtures.sol";

import { TickMath } from "../../../src/libraries/TickMath.sol";

contract TestUsdnProtocolTicks is UsdnProtocolBaseFixture {
    function setUp() public {
        super._setUp(DEFAULT_PARAMS);
    }

    /**
     * @custom:scenario Convert a price to a tick while rounding towards negative infinity
     * @custom:given A price between `TickMath.MIN_PRICE` and `uint128.max`
     * @custom:when The effective tick for the price is calculated
     * @custom:then The result is the closest valid tick towards negative infinity
     * @custom:and The price corresponding to that tick is always lower than or equal to the input price
     * @custom:and For larger prices, the next valid tick towards positive infinity would lead to a price that is
     * higher than the input price
     * @param price The price to convert to a tick
     */
    function testFuzz_liqPrice(uint128 price) public view {
        price = uint128(bound(uint256(price), TickMath.MIN_PRICE, type(uint128).max));
        int24 closestTickDown = TickMath.getTickAtPrice(price);
        int24 tick = protocol.getEffectiveTickForPrice(price); // next valid tick towards infinity
        // make sure we rounded down (except at low end)
        // e.g. if desired price is 1000, the closest tick down is -34_556, but the min usable tick is -34_550
        closestTickDown = int24(FixedPointMathLib.max(int256(closestTickDown), int256(protocol.minTick())));
        assertLe(tick, closestTickDown, "tick <= closestTickDown");
        // make sure the effective liquidation price is always <= the desired liquidation price (except at low end)
        // e.g. if desired price is 1000, the lowest usable tick gives a price of 1006, so the effective price is 1006
        price = uint128(FixedPointMathLib.max(uint256(price), uint256(TickMath.getPriceAtTick(protocol.minTick()))));
        uint128 effLiqPrice = protocol.getEffectivePriceForTick(tick);
        assertLe(effLiqPrice, price, "effLiqPrice <= price");
        // for very small prices, the `getEffectiveTickForPrice` result might not be the best tick to use to represent
        // the price due to rounding errors. But for all other prices, we can be sure that the next valid tick towards
        // positive infinity would lead to a price that is too high.
        if (price > 5_000_000) {
            int24 nextTick = tick + protocol.getTickSpacing(); // the next valid tick towards positive infinity
            uint256 nextPrice = TickMath.getPriceAtTick(nextTick);
            // this next tick would lead to a price that is higher than the initial price
            assertLt(price, nextPrice, "price < nextPrice");
        }
    }
}

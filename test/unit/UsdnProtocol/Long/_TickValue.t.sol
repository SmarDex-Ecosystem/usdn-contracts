// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { UsdnProtocolBaseFixture } from "../utils/Fixtures.sol";

import { HugeUint } from "../../../../src/libraries/HugeUint.sol";

/// @custom:feature the _tickValue internal function of the UsdnProtocolLong contract.
contract TestUsdnProtocolLongTickValue is UsdnProtocolBaseFixture {
    function setUp() public {
        super._setUp(DEFAULT_PARAMS);
    }

    /**
     * @custom:scenario Check calculations of the `tickValue` function
     * @custom:given A tick with total expo 10 wstETH and a liquidation price around $500
     * @custom:when The current price is equal to the liquidation price without penalty
     * @custom:or the current price is 2x the liquidation price without penalty
     * @custom:or the current price is 0.5x the liquidation price without penalty
     * @custom:or the current price is equal to the liquidation price with penalty
     * @custom:then The tick value is 0 if the price is equal to the liquidation price without penalty
     * @custom:or the tick value is approx. 5 wstETH if the price is 2x the liquidation price without penalty
     * @custom:or the tick value is -10 wstETH if the price is 0.5x the liquidation price without penalty
     * @custom:or the tick value is 0.198003465594229687 wstETH if the price is equal to the liquidation price with
     * penalty
     */
    function test_tickValue() public view {
        int24 tick = protocol.getEffectiveTickForPrice(500 ether);
        uint128 liqPriceWithoutPenalty = protocol.getEffectivePriceForTick(protocol.i_calcTickWithoutPenalty(tick));
        TickData memory tickData =
            TickData({ totalExpo: 10 ether, totalPos: 1, liquidationPenalty: protocol.getLiquidationPenalty() });

        int256 value =
            protocol.i_tickValue(tick, liqPriceWithoutPenalty, 0, HugeUint.Uint512({ hi: 0, lo: 0 }), tickData);
        assertEq(value, 0, "current price = liq price");

        value = protocol.i_tickValue(tick, liqPriceWithoutPenalty * 2, 0, HugeUint.Uint512({ hi: 0, lo: 0 }), tickData);
        assertApproxEqAbs(value, 5 ether, 1, "current price = 2x liq price");

        value = protocol.i_tickValue(tick, liqPriceWithoutPenalty / 2, 0, HugeUint.Uint512({ hi: 0, lo: 0 }), tickData);
        assertEq(value, -10 ether, "current price = 0.5x liq price");

        value = protocol.i_tickValue(
            tick, protocol.getEffectivePriceForTick(tick), 0, HugeUint.Uint512({ hi: 0, lo: 0 }), tickData
        );
        assertEq(value, 0.198003465594229687 ether, "current price = liq price with penalty");
    }
}

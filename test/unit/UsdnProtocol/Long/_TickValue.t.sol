// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { HugeUint } from "@smardex-solidity-libraries-1/HugeUint.sol";

import { UsdnProtocolBaseFixture } from "../utils/Fixtures.sol";

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
     * @custom:or the tick value is 5 wstETH if the price is 2x the liquidation price without penalty
     * @custom:or the tick value is -10 wstETH if the price is 0.5x the liquidation price without penalty
     * @custom:or the tick value is as expected if the price is equal to the liquidation price with penalty
     */
    function test_tickValue() public view {
        int24 tick = protocol.getEffectiveTickForPrice(500 ether, 0, 0, HugeUint.wrap(0), protocol.getTickSpacing());
        uint128 liqPriceWithoutPenalty =
            protocol.getEffectivePriceForTick(protocol.i_calcTickWithoutPenalty(tick), 0, 0, HugeUint.wrap(0));
        TickData memory tickData =
            TickData({ totalExpo: 10 ether, totalPos: 1, liquidationPenalty: protocol.getLiquidationPenalty() });

        int256 value = protocol.i_tickValue(tick, liqPriceWithoutPenalty, 0, HugeUint.wrap(0), tickData);
        assertEq(value, 0, "current price = liq price");

        value = protocol.i_tickValue(tick, liqPriceWithoutPenalty * 2, 0, HugeUint.wrap(0), tickData);
        assertEq(value, 5 ether, "current price = 2x liq price");

        value = protocol.i_tickValue(tick, liqPriceWithoutPenalty / 2, 0, HugeUint.wrap(0), tickData);
        assertEq(value, -10 ether, "current price = 0.5x liq price");

        uint128 currentPrice = protocol.getEffectivePriceForTick(tick, 0, 0, HugeUint.wrap(0));
        value = protocol.i_tickValue(tick, currentPrice, 0, HugeUint.wrap(0), tickData);
        int256 expectedValue = int256(tickData.totalExpo * (currentPrice - liqPriceWithoutPenalty) / currentPrice);
        assertEq(value, expectedValue, "current price = liq price with penalty");
    }
}

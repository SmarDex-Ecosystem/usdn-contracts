// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { ADMIN } from "test/utils/Constants.sol";
import { UsdnProtocolBaseFixture } from "test/unit/UsdnProtocol/utils/Fixtures.sol";

import { TickData, ProtocolAction } from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";

/// @custom:feature The `GetTickLiquidationPenalty` function of the long layer
contract TestUsdnProtocolGetTickLiquidationPenalty is UsdnProtocolBaseFixture {
    function setUp() external {
        _setUp(DEFAULT_PARAMS);
    }

    /**
     * @custom:scenario Check the return value of the function when the tick is empty
     * @custom:given An empty tick
     * @custom:when We call the function
     * @custom:then The function should return the current value of the liquidation penalty setting
     */
    function test_getTickLiquidationPenaltyEmpty() external {
        uint8 startPenalty = protocol.getLiquidationPenalty();
        int24 tick = 69_420;
        TickData memory tickData = protocol.getTickData(tick);
        assertEq(tickData.totalPos, 0, "empty tick");

        // check initial value
        assertEq(protocol.getTickLiquidationPenalty(tick), startPenalty, "initial value");

        // change the penalty setting
        vm.prank(ADMIN);
        protocol.setLiquidationPenalty(startPenalty + 1);

        // check new value
        assertEq(protocol.getTickLiquidationPenalty(tick), startPenalty + 1, "new value");
    }

    /**
     * @custom:scenario Check the return value of the function when the tick is populated
     * @custom:given A populated tick using the initial liquidation penalty value
     * @custom:when We call the function after changing the liquidation penalty setting
     * @custom:then The function should return the initial value as stored in the tick
     */
    function test_getTickLiquidationPenaltyPopulated() external {
        uint8 startPenalty = protocol.getLiquidationPenalty();
        (int24 tick,,) = setUpUserPositionInLong(
            address(this), ProtocolAction.ValidateOpenPosition, 10 ether, params.initialPrice / 2, params.initialPrice
        );
        assertEq(protocol.getTickLiquidationPenalty(tick), startPenalty, "tick value");

        // change the penalty setting
        vm.prank(ADMIN);
        protocol.setLiquidationPenalty(startPenalty - 1);

        // check value hasn't changed
        assertEq(protocol.getTickLiquidationPenalty(tick), startPenalty, "new value");
    }
}

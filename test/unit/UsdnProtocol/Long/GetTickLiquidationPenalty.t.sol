// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { ADMIN } from "../../../utils/Constants.sol";
import { UsdnProtocolBaseFixture } from "../utils/Fixtures.sol";

/// @custom:feature The `GetTickLiquidationPenalty` function of the long layer
contract TestUsdnProtocolGetTickLiquidationPenalty is UsdnProtocolBaseFixture {
    function setUp() public {
        _setUp(DEFAULT_PARAMS);
    }

    /**
     * @custom:scenario Check the return value of the function when the tick is empty
     * @custom:given An empty tick
     * @custom:when We call the function
     * @custom:then The function should return the current value of the liquidation penalty setting
     */
    function test_getTickLiquidationPenaltyEmpty() public adminPrank {
        uint24 startPenalty = protocol.getLiquidationPenalty();
        int24 tick = 69_420;
        TickData memory tickData = protocol.getTickData(tick);
        assertEq(tickData.totalPos, 0, "empty tick");

        // check initial value
        assertEq(protocol.getTickLiquidationPenalty(tick), startPenalty, "initial value");

        // change the penalty setting
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
    function test_getTickLiquidationPenaltyPopulated() public {
        uint24 startPenalty = protocol.getLiquidationPenalty();
        PositionId memory posId = setUpUserPositionInLong(
            OpenParams({
                user: address(this),
                untilAction: ProtocolAction.ValidateOpenPosition,
                positionSize: 10 ether,
                desiredLiqPrice: params.initialPrice / 2,
                price: params.initialPrice
            })
        );
        assertEq(protocol.getTickLiquidationPenalty(posId.tick), startPenalty, "tick value");

        // change the penalty setting
        vm.prank(ADMIN);
        protocol.setLiquidationPenalty(startPenalty - 1);

        // check value hasn't changed
        assertEq(protocol.getTickLiquidationPenalty(posId.tick), startPenalty, "new value");
    }

    /**
     * @custom:scenario Check the return value of the function when the tick was liquidated
     * @custom:given A tick that had a position and then was liquidated
     * @custom:when We call the function after changing the liquidation penalty setting
     * @custom:then The function should return the new value for the liquidation penalty
     */
    function test_getTickLiquidationPenaltyLiquidated() public {
        uint24 startPenalty = protocol.getLiquidationPenalty();
        PositionId memory posId = setUpUserPositionInLong(
            OpenParams({
                user: address(this),
                untilAction: ProtocolAction.ValidateOpenPosition,
                positionSize: 10 ether,
                desiredLiqPrice: params.initialPrice / 2,
                price: params.initialPrice
            })
        );

        // we need to skip 1 minute to make the new price data fresh
        skip(1 minutes);
        assertEq(protocol.getTickLiquidationPenalty(posId.tick), startPenalty, "tick value");
        _waitBeforeLiquidation();
        protocol.mockLiquidate(abi.encode(params.initialPrice / 3), 10);

        // change the penalty setting
        vm.prank(ADMIN);
        protocol.setLiquidationPenalty(startPenalty - 1);

        // the tick has now the new value
        assertEq(protocol.getTickLiquidationPenalty(posId.tick), startPenalty - 1, "new value");
    }

    /**
     * @custom:scenario Check the return value of the function when the tick had a position that is now closed
     * @custom:given A tick that had a position, but the position was later closed
     * @custom:when We call the function after changing the liquidation penalty setting
     * @custom:then The function should return the new value for the liquidation penalty
     */
    function test_getTickLiquidationPenaltyWasPopulatedNowEmpty() public {
        uint24 startPenalty = protocol.getLiquidationPenalty();
        PositionId memory posId = setUpUserPositionInLong(
            OpenParams({
                user: address(this),
                untilAction: ProtocolAction.ValidateClosePosition,
                positionSize: 10 ether,
                desiredLiqPrice: params.initialPrice / 2,
                price: params.initialPrice
            })
        );
        // change the penalty setting
        vm.prank(ADMIN);
        protocol.setLiquidationPenalty(startPenalty - 1);

        assertEq(protocol.getTickLiquidationPenalty(posId.tick), startPenalty - 1, "final value");
    }
}

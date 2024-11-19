// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { UsdnProtocolBaseFixture } from "../utils/Fixtures.sol";

/**
 * @custom:feature Test the _findHighestPopulatedTick internal function of the UsdnProtocolLong contract
 * @custom:background Given an initialized USDN Protocol with default parameters
 */
contract TestUsdnProtocolLongFindHighestPopulatedTick is UsdnProtocolBaseFixture {
    function setUp() public {
        super._setUp(DEFAULT_PARAMS);
    }

    /**
     * @custom:scenario Find the highest populated tick
     * @custom:given The initial position
     * @custom:and a position in a higher tick
     * @custom:when we call _findHighestPopulatedTick
     * @custom:then we get the highest populated tick from the tick provided
     */
    function test_findHighestPopulatedTick() public {
        PositionId memory posId = setUpUserPositionInLong(
            OpenParams({
                user: address(this),
                untilAction: ProtocolAction.ValidateOpenPosition,
                positionSize: 1 ether,
                desiredLiqPrice: DEFAULT_PARAMS.initialPrice - 400 ether,
                price: DEFAULT_PARAMS.initialPrice
            })
        );

        // Add a position in a higher liquidation tick to check the result changes
        int24 highestPopulatedTick = protocol.i_findHighestPopulatedTick(type(int24).max);
        assertEq(highestPopulatedTick, posId.tick, "The tick of the newly created position should have been found");

        // Search from lower than the higher tick previously populated
        highestPopulatedTick = protocol.i_findHighestPopulatedTick(posId.tick - protocol.getTickSpacing());
        assertEq(
            highestPopulatedTick,
            initialPosition.tick,
            "The tick lower than the newly created position should have been found"
        );
    }

    /**
     * @custom:scenario There are no populated ticks below the tick to search from
     * @custom:given The initialization position
     * @custom:when we call _findHighestPopulatedTick from a tick below its liquidation price
     * @custom:then the minimum usable tick is returned
     */
    function test_findHighestPopulatedTickWhenNothingFound() public view {
        int24 result = protocol.i_findHighestPopulatedTick(initialPosition.tick - protocol.getTickSpacing());
        assertEq(result, protocol.minTick(), "No tick should have been found (min usable tick returned)");
    }
}

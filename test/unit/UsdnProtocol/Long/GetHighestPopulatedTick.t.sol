// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { UsdnProtocolBaseFixture } from "../utils/Fixtures.sol";

/**
 * @custom:feature Test the {getHighestPopulatedTick} function
 * @custom:background Given an initialized USDN Protocol with default parameters
 */
contract TestUsdnProtocolGetHighestPopulatedTick is UsdnProtocolBaseFixture {
    function setUp() public {
        super._setUp(DEFAULT_PARAMS);
    }

    /**
     * @custom:scenario There are no populated ticks below the tick to search from
     * @custom:given The initialization position
     * @custom:when we call {getHighestPopulatedTick} from a tick below its liquidation price
     * @custom:then the minimum usable tick is returned
     */
    function test_getHighestPopulatedTick() public view {
        int24 result = protocol.getHighestPopulatedTick();
        assertEq(result, initialPosition.tick, "The tick of the initial position should have been returned");
    }

    /**
     * @custom:scenario Get the highest populated tick but the value in storage is out of date
     * @custom:given The initial position
     * @custom:and A position opened at a higher tick and closed
     * @custom:when we call {getHighestPopulatedTick}
     * @custom:then the tick of the initial position is returned
     */
    function test_getHighestPopulatedTickWhenStorageOutOfDate() public {
        // open and close a position to update the highest populated tick during the open
        // and make it out of date after the close
        PositionId memory posId = setUpUserPositionInLong(
            OpenParams({
                user: address(this),
                untilAction: ProtocolAction.ValidateOpenPosition,
                positionSize: 1 ether,
                desiredLiqPrice: DEFAULT_PARAMS.initialPrice - 400 ether,
                price: DEFAULT_PARAMS.initialPrice
            })
        );

        // sanity check
        int24 highestPopulatedTick = protocol.getHighestPopulatedTick();
        assertEq(highestPopulatedTick, posId.tick, "The tick of the newly created position should have been returned");

        // close the position to make the `highestPopulatedTick` storage variable out of date
        protocol.initiateClosePosition(
            posId,
            1 ether,
            DISABLE_MIN_PRICE,
            address(this),
            payable(address(this)),
            type(uint256).max,
            abi.encode(DEFAULT_PARAMS.initialPrice),
            EMPTY_PREVIOUS_DATA,
            ""
        );
        _waitDelay();
        protocol.validateClosePosition(
            payable(address(this)), abi.encode(DEFAULT_PARAMS.initialPrice), EMPTY_PREVIOUS_DATA
        );

        int24 highestPopulatedTickInStorage = protocol.getHighestPopulatedTickFromStorage();
        assertEq(
            highestPopulatedTickInStorage,
            highestPopulatedTick,
            "The highest populated tick should not have been updated"
        );

        highestPopulatedTick = protocol.getHighestPopulatedTick();
        assertEq(
            highestPopulatedTick,
            initialPosition.tick,
            "The tick of the initial position should have been returned even though the value in storage is out of date"
        );
    }
}

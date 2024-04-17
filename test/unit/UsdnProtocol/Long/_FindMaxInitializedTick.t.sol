// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { UsdnProtocolBaseFixture } from "test/unit/UsdnProtocol/utils/Fixtures.sol";

import { ProtocolAction } from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";

/// @custom:feature Test the _findMaxInitializedTick internal function of the long layer
contract TestUsdnProtocolLongFindMaxInitializedTick is UsdnProtocolBaseFixture {
    int24 _tick;

    function setUp() public {
        super._setUp(DEFAULT_PARAMS);

        // Tick of the position created by the initialization of the protocol
        _tick = protocol.getEffectiveTickForPrice(DEFAULT_PARAMS.initialPrice / 2)
            + int24(uint24(protocol.getLiquidationPenalty())) * protocol.getTickSpacing();
    }

    /**
     * @custom:scenario Find the max initialized tick
     * @custom:given The initialization position
     * @custom:and a position in a higher tick
     * @custom:when we call _findMaxInitializedTick
     * @custom:then we get the highest populated tick from the tick provided
     */
    function test_findMaxInitializedTick() public {
        int24 maxInitializedTick = protocol.i_findMaxInitializedTick(type(int24).max);
        assertEq(maxInitializedTick, _tick, "The tick of protocol initialization should have been found");

        (int24 higherTick,,) = setUpUserPositionInLong(
            address(this),
            ProtocolAction.ValidateOpenPosition,
            1 ether,
            DEFAULT_PARAMS.initialPrice - 400 ether,
            DEFAULT_PARAMS.initialPrice
        );

        // Add a position in a higher liquidation tick to check the result changes
        maxInitializedTick = protocol.i_findMaxInitializedTick(type(int24).max);
        assertEq(maxInitializedTick, higherTick, "The tick of the newly created position should have been found");

        // Search from lower than the higher tick previously populated
        maxInitializedTick = protocol.i_findMaxInitializedTick(higherTick - 1);
        assertEq(maxInitializedTick, _tick, "The tick lower than the newly created position should have been found");
    }

    /**
     * @custom:scenario There are no populated ticks below the tick to search from
     * @custom:given The initialization position
     * @custom:when we call _findMaxInitializedTick from a tick below its liquidation price
     * @custom:then the minimum usable tick is returned
     */
    function test_findMaxInitializedTickWhenNothingFound() public {
        int24 result = protocol.i_findMaxInitializedTick(_tick - 1);
        assertEq(result, protocol.minTick(), "No tick should have been found (min usable tick returned)");
    }
}

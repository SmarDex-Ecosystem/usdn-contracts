// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { UsdnProtocolBaseFixture } from "test/unit/UsdnProtocol/utils/Fixtures.sol";

import { TickMath } from "src/libraries/TickMath.sol";

/// @custom:feature Test the _tickToBitmapIndex internal function of the long layer
contract TestUsdnProtocolLongTickToBitmapIndex is UsdnProtocolBaseFixture {
    int24 _tickSpacing;
    int24 _minTick;
    int24 _maxTick;

    function setUp() public {
        super._setUp(DEFAULT_PARAMS);

        _tickSpacing = protocol.getTickSpacing();
        _minTick = protocol.minTick();
        _maxTick = protocol.maxTick();
    }

    /**
     * @custom:scenario Get the index for the minimum usable tick
     * @custom:given The minimum usable tick
     * @custom:when _tickToBitmapIndex is called
     * @custom:then The index 0 is returned
     */
    function test_tickToBitmapIndexWithMinTick() public {
        uint256 result = protocol.i_tickToBitmapIndex(_minTick, _tickSpacing);

        assertEq(result, 0, "The result should be 0 (lowest possible index)");
    }

    /**
     * @custom:scenario Get the index for the maximum usable tick
     * @custom:given The maximum usable tick
     * @custom:when _tickToBitmapIndex is called
     * @custom:then The max index is returned
     */
    function test_tickToBitmapIndexWithMaxTick() public {
        uint256 maxIndex = uint256(int256(_maxTick - _minTick) / _tickSpacing);
        uint256 result = protocol.i_tickToBitmapIndex(_maxTick, _tickSpacing);

        assertEq(result, maxIndex, "The result should be the highest calculable index");
    }

    /**
     * @custom:scenario Check the calculations of _tickToBitmapIndex with different ticks and tick spacing
     * @custom:given a tick between the min and max usable ticks
     * @custom:and a tick spacing between 1 (0.01%) and 1000 (10%)
     * @custom:when _tickToBitmapIndex is called
     * @custom:then The expected index is returned
     * @custom:and The returned index can be transformed back into the original tick
     * @custom:and The returned indexes are unique and sequential
     * @param tick The tick corresponding to the bitmap index (multiple of the tick spacing)
     * @param tickSpacing The tick spacing to use for the calculations
     */
    function testFuzz_tickToBitmapIndex(int24 tick, int24 tickSpacing) public {
        tickSpacing = int24(bound(tickSpacing, 1, 1000));
        // Bound the tick to values that are multiples of the tick spacing
        tick = int24(bound(tick, _minTick / tickSpacing, _maxTick / tickSpacing)) * tickSpacing;

        uint256 expectedIndex = uint256(int256(tick) / tickSpacing - TickMath.MIN_TICK / tickSpacing);
        uint256 index = protocol.i_tickToBitmapIndex(tick, tickSpacing);
        assertEq(index, expectedIndex, "The result should be the expected value");

        int24 tickFromIndex = protocol.i_bitmapIndexToTick(index, tickSpacing);
        assertEq(tick, tickFromIndex, "The tick found from the index should be equal to the original tick");

        /* -------------- Check that indexes are unique and sequential -------------- */
        // Avoid underflow
        if (index > 0) {
            uint256 resultMinus = protocol.i_tickToBitmapIndex(tick - tickSpacing, tickSpacing);
            assertEq(index - 1, resultMinus, "The result should be the original index minus 1");
        }

        uint256 resultPlus = protocol.i_tickToBitmapIndex(tick + tickSpacing, tickSpacing);
        assertEq(index + 1, resultPlus, "The result should be the original index plus 1");
    }
}

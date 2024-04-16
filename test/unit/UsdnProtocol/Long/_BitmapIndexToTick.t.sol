// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { UsdnProtocolBaseFixture } from "test/unit/UsdnProtocol/utils/Fixtures.sol";

import { TickMath } from "src/libraries/TickMath.sol";

/// @custom:feature Test the _bitmapIndexToTick internal function of the long layer
contract TestUsdnProtocolLongBitmapIndexToTick is UsdnProtocolBaseFixture {
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
     * @custom:scenario Check that the minimum usable tick is at index 0
     * @custom:given The index 0
     * @custom:when _bitmapIndexToTick is called
     * @custom:then The minimum usable tick is returned
     */
    function test_bitmapIndexToTickWithMinIndex() public {
        int24 tick = protocol.i_bitmapIndexToTick(0, _tickSpacing);

        assertEq(tick, _minTick, "The result should be the minimum usable tick");
    }

    /**
     * @custom:scenario Check that the maximum usable tick is at the highest calculable index
     * @custom:given The highest calculable index
     * @custom:when _bitmapIndexToTick is called
     * @custom:then The maximum usable tick is returned
     */
    function test_bitmapIndexToTickWithMaxIndex() public {
        uint256 maxIndex = uint256(int256(_maxTick - _minTick) / _tickSpacing);
        int24 tick = protocol.i_bitmapIndexToTick(maxIndex, _tickSpacing);

        assertEq(tick, _maxTick, "The result should be the maximum usable tick");
    }

    /**
     * @custom:scenario Check the calculations of _bitmapIndexToTick with different indexes and tick spacing
     * @custom:given an index between 0 and the highest calculable index
     * @custom:and a tick spacing between 1 (0.01%) and 1000 (10%)
     * @custom:when _bitmapIndexToTick is called
     * @custom:then The expected tick is returned
     * @custom:and The returned tick can be transformed back into the original index
     * @custom:and The returned ticks are unique and sequential (separated by the tick spacing)
     * @param index The index of the tick in the bitmap
     * @param tickSpacing The tick spacing to use for the calculations
     */
    function testFuzz_bitmapIndexToTick(uint256 index, int24 tickSpacing) public {
        tickSpacing = int24(bound(tickSpacing, 1, 1000));
        // Bound the tick to values that are multiples of the tick spacing
        index = bound(index, 0, uint256((int256(_maxTick) - _minTick) / tickSpacing));

        int24 expectedTick = int24(((int256(index) + TickMath.MIN_TICK / tickSpacing) * tickSpacing));
        int24 tick = protocol.i_bitmapIndexToTick(index, tickSpacing);
        assertEq(tick, expectedTick, "The result should be the expected value");

        uint256 indexFromTick = protocol.i_tickToBitmapIndex(tick, tickSpacing);
        assertEq(index, indexFromTick, "The index found from the tick should be equal to the original index");

        /* --------------- Check that ticks are unique and sequential --------------- */
        // Avoid underflow
        if (index > 0) {
            int24 resultMinus = protocol.i_bitmapIndexToTick(index - 1, tickSpacing);
            assertEq(tick - tickSpacing, resultMinus, "The result should be the original index minus tick spacing");
        }

        int24 resultPlus = protocol.i_bitmapIndexToTick(index + 1, tickSpacing);
        assertEq(tick + tickSpacing, resultPlus, "The result should be the original index plus tick spacing");
    }
}

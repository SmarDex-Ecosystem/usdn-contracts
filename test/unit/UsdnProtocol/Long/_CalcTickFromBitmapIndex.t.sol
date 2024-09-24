// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { UsdnProtocolBaseFixture } from "../utils/Fixtures.sol";

import { TickMath } from "../../../../src/libraries/TickMath.sol";

/// @custom:feature Test the _calcTickFromBitmapIndex internal function of the long layer
contract TestUsdnProtocolLongCalcTickFromBitmapIndex is UsdnProtocolBaseFixture {
    int24 _minTick;
    int24 _maxTick;

    function setUp() public {
        super._setUp(DEFAULT_PARAMS);

        _minTick = protocol.minTick();
        _maxTick = TickMath.maxUsableTick(protocol.getTickSpacing());
    }

    /**
     * @custom:scenario Check that the minimum usable tick is at index 0
     * @custom:given The index 0
     * @custom:when _calcTickFromBitmapIndex is called
     * @custom:then The minimum usable tick is returned
     */
    function test_calcTickFromBitmapIndexWithMinIndex() public view {
        int24 tick = protocol.i_calcTickFromBitmapIndex(0);

        assertEq(tick, _minTick, "The result should be the minimum usable tick");
    }

    /**
     * @custom:scenario Check that the maximum usable tick is at the highest calculable index
     * @custom:given The highest calculable index
     * @custom:when _calcTickFromBitmapIndex is called
     * @custom:then The maximum usable tick is returned
     */
    function test_calcTickFromBitmapIndexWithMaxIndex() public view {
        uint256 maxIndex = uint256(int256(_maxTick - _minTick) / protocol.getTickSpacing());
        int24 tick = protocol.i_calcTickFromBitmapIndex(maxIndex);

        assertEq(tick, _maxTick, "The result should be the maximum usable tick");
    }

    /**
     * @custom:scenario Check the calculations of _calcTickFromBitmapIndex with different indexes and tick spacing
     * @custom:given an index between 0 and the highest calculable index
     * @custom:and a tick spacing between 1 (0.01%) and 1000 (10.52%)
     * @custom:when _calcTickFromBitmapIndex is called
     * @custom:then The expected tick is returned
     * @custom:and The returned tick can be transformed back into the original index
     * @custom:and The returned ticks are unique and sequential (separated by the tick spacing)
     * @param index The index of the tick in the bitmap
     * @param tickSpacing The tick spacing to use for the calculations
     */
    function testFuzz_calcTickFromBitmapIndex(uint256 index, int24 tickSpacing) public view {
        tickSpacing = int24(bound(tickSpacing, 1, 1000));
        // Bound the tick to values that are multiples of the tick spacing
        index = bound(index, 0, uint256((int256(_maxTick) - _minTick) / tickSpacing));

        int24 expectedTick = int24(((int256(index) + TickMath.MIN_TICK / tickSpacing) * tickSpacing));
        int24 tick = protocol.i_calcTickFromBitmapIndex(index, tickSpacing);
        assertEq(tick, expectedTick, "The result should be the expected value");

        uint256 indexFromTick = protocol.i_calcBitmapIndexFromTick(tick, tickSpacing);
        assertEq(index, indexFromTick, "The index found from the tick should be equal to the original index");

        /* --------------- Check that ticks are unique and sequential --------------- */
        // Avoid underflow
        if (index > 0) {
            int24 resultMinus = protocol.i_calcTickFromBitmapIndex(index - 1, tickSpacing);
            assertEq(tick - tickSpacing, resultMinus, "The result should be the original index minus tick spacing");
        }

        int24 resultPlus = protocol.i_calcTickFromBitmapIndex(index + 1, tickSpacing);
        assertEq(tick + tickSpacing, resultPlus, "The result should be the original index plus tick spacing");
    }
}

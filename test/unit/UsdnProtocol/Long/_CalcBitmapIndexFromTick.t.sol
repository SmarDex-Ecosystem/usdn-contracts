// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { UsdnProtocolBaseFixture } from "../utils/Fixtures.sol";

import { TickMath } from "../../../../src/libraries/TickMath.sol";

/// @custom:feature Test the _calcBitmapIndexFromTick internal function of the long layer
contract TestUsdnProtocolLongCalcBitmapIndexFromTick is UsdnProtocolBaseFixture {
    int24 _minTick;
    int24 _maxTick;

    function setUp() public {
        super._setUp(DEFAULT_PARAMS);

        _minTick = protocol.minTick();
        _maxTick = TickMath.maxUsableTick(protocol.getTickSpacing());
    }

    /**
     * @custom:scenario Get the index for the minimum usable tick
     * @custom:given The minimum usable tick
     * @custom:when _calcBitmapIndexFromTick is called
     * @custom:then The index 0 is returned
     */
    function test_calcBitmapIndexFromTickWithMinTick() public view {
        uint256 result = protocol.i_calcBitmapIndexFromTick(_minTick);

        assertEq(result, 0, "The result should be 0 (lowest possible index)");
    }

    /**
     * @custom:scenario Get the index for the maximum usable tick
     * @custom:given The maximum usable tick
     * @custom:when _calcBitmapIndexFromTick is called
     * @custom:then The max index is returned
     */
    function test_calcBitmapIndexFromTickWithMaxTick() public view {
        uint256 maxIndex = uint256(int256(_maxTick - _minTick) / protocol.getTickSpacing());
        uint256 result = protocol.i_calcBitmapIndexFromTick(_maxTick);

        assertEq(result, maxIndex, "The result should be the highest calculable index");
    }

    /**
     * @custom:scenario Check the calculations of _calcBitmapIndexFromTick with different ticks and tick spacing
     * @custom:given a tick between the min and max usable ticks
     * @custom:and a tick spacing between 1 (0.01%) and 1000 (10.52%)
     * @custom:when _calcBitmapIndexFromTick is called
     * @custom:then The expected index is returned
     * @custom:and The returned index can be transformed back into the original tick
     * @custom:and The returned indexes are unique and sequential
     * @param tick The tick corresponding to the bitmap index (multiple of the tick spacing)
     * @param tickSpacing The tick spacing to use for the calculations
     */
    function testFuzz_calcBitmapIndexFromTick(int24 tick, int24 tickSpacing) public view {
        tickSpacing = int24(bound(tickSpacing, 1, 1000));
        // Bound the tick to values that are multiples of the tick spacing
        tick = int24(bound(tick, _minTick / tickSpacing, _maxTick / tickSpacing)) * tickSpacing;

        uint256 expectedIndex = uint256(int256(tick) / tickSpacing - TickMath.MIN_TICK / tickSpacing);
        uint256 index = protocol.i_calcBitmapIndexFromTick(tick, tickSpacing);
        assertEq(index, expectedIndex, "The result should be the expected value");

        int24 tickFromIndex = protocol.i_calcTickFromBitmapIndex(index, tickSpacing);
        assertEq(tick, tickFromIndex, "The tick found from the index should be equal to the original tick");

        /* -------------- Check that indexes are unique and sequential -------------- */
        // Avoid underflow
        if (index > 0) {
            uint256 resultMinus = protocol.i_calcBitmapIndexFromTick(tick - tickSpacing, tickSpacing);
            assertEq(index - 1, resultMinus, "The result should be the original index minus 1");
        }

        uint256 resultPlus = protocol.i_calcBitmapIndexFromTick(tick + tickSpacing, tickSpacing);
        assertEq(index + 1, resultPlus, "The result should be the original index plus 1");
    }
}

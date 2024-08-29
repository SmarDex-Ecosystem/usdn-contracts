// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { FixedPointMathLib } from "solady/src/utils/FixedPointMathLib.sol";

import { UsdnProtocolBaseFixture } from "../utils/Fixtures.sol";

import { UsdnProtocolConstantsLibrary as Constants } from
    "../../../../src/UsdnProtocol/libraries/UsdnProtocolConstantsLibrary.sol";
import { UsdnProtocolLongLibrary as Long } from "../../../../src/UsdnProtocol/libraries/UsdnProtocolLongLibrary.sol";
import { TickMath } from "../../../../src/libraries/TickMath.sol";

/**
 * @custom:feature The _roundTickDownWithPenalty internal function of the UsdnProtocolLongLibrary
 */
contract TestUsdnProtocolLongCheckSafetyMargin is UsdnProtocolBaseFixture {
    using SafeCast for uint256;

    function setUp() public {
        super._setUp(DEFAULT_PARAMS);
    }

    /**
     * @custom:scenario The _roundTickDownWithPenalty function gives the expected result
     * @custom:given A tick spacing between 1 and 1000 ticks
     * @custom:and A liquidation penalty between 0 and MAX_LIQUIDATION_PENALTY
     * @custom:and A tick with penalty between MIN_TICK+liqPenalty and MAX_TICK+liqPenalty
     * @custom:when The tick is rounded down
     * @custom:then The rounded tick is at least MIN_TICK+liqPenalty
     * @custom:and The rounded tick is a multiple of tickSpacing
     * @custom:and The rounded tick is smaller than or equal to the original tick, except if it was bounded by
     * MIN_TICK+liqPenalty
     */
    function testFuzz_roundTickDownWithPenalty(int24 tickWithPenalty, int24 tickSpacing, uint24 liqPenalty)
        public
        pure
    {
        tickSpacing = int24(bound(tickSpacing, 1, 1000));
        liqPenalty = uint24(bound(liqPenalty, 0, Constants.MAX_LIQUIDATION_PENALTY));
        int24 minTickWithPenalty = TickMath.MIN_TICK + int24(liqPenalty);
        tickWithPenalty = int24(bound(tickWithPenalty, minTickWithPenalty, TickMath.MAX_TICK + int24(liqPenalty)));
        int24 tick = Long._roundTickDownWithPenalty(tickWithPenalty, tickSpacing, liqPenalty);
        assertGe(tick, minTickWithPenalty, "at least min tick with penalty");
        assertEq(tick % tickSpacing, 0, "multiple of tickSpacing");
        if (tickWithPenalty < 0) {
            int24 roundedTick = -int24(int256(FixedPointMathLib.divUp(uint256(int256(-tickWithPenalty)), uint256(int256(tickSpacing)))))
                * tickSpacing;
            // we can only assert that the result is lte to the original if the rounded tick was at least
            // equal to the minimum bound. If the simple rounding brought the tick below the min bound, then the
            // final result will be necessarily higher than the original
            if (roundedTick >= minTickWithPenalty) {
                assertLe(tick, tickWithPenalty, "rounded down");
            }
        } else {
            assertLe(tick, tickWithPenalty, "rounded down (positive)");
        }
    }
}

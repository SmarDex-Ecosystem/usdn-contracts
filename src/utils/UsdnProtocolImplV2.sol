// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import { UsdnProtocolImpl } from "../../../../src/UsdnProtocol/UsdnProtocolImpl.sol";

import { TickMath } from "../../../../src/libraries/TickMath.sol";
import { IUsdnProtocolImplV2 } from "../../test/unit/UsdnProtocol/utils/IUsdnProtocolImplV2.sol";
import { FixedPointMathLib } from "solady/src/utils/FixedPointMathLib.sol";

/// @custom:oz-upgrades-from UsdnProtocolImpl
contract UsdnProtocolImplV2 is UsdnProtocolImpl, IUsdnProtocolImplV2 {
    uint256 public newVariable;

    function initializeV2(address newFallback) public reinitializer(2) {
        newVariable = 1;
        s._protocolFallbackAddr = newFallback;
    }

    function retBool() public pure returns (bool) {
        return true;
    }

    function makeItBig() public pure {
        uint256 newVariable2 = 100;
        bool test = true;
        uint256 test2 = 100 * 100 * newVariable2;
        int256 test3 = -100;
        int24 tickWithPenalty_ = 1000;
        uint24 liqPenalty = 1000;
        int24 roundedTick_ = 100;
        int24 tickSpacing = 100;
        int24 tickWithPenalty = 98;
        test = test2 > 1000;
        tickWithPenalty_ = 0;

        if (test3 < 0) {
            roundedTick_ = -int24(int256(FixedPointMathLib.divUp(uint256(int256(-test3)), uint256(int256(tickSpacing)))))
                * tickSpacing;
            int24 minTickWithPenalty = TickMath.MIN_TICK + int24(liqPenalty);
            if (roundedTick_ < minTickWithPenalty) {
                roundedTick_ = minTickWithPenalty - (minTickWithPenalty % tickSpacing);
            }
        } else {
            roundedTick_ = (tickWithPenalty / tickSpacing) * tickSpacing;
        }
    }
}

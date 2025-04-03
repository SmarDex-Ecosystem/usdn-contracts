// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.26;

import "./PropertiesBase.sol";

/**
 * @notice Global protocol invariants
 * @dev Covers fundamental properties that should always hold true across all flows
 */
abstract contract Properties_GLOB is PropertiesBase {
    function invariant_GLOB_01() internal {
        if (states[1].highestActualTick != 0) {
            fl.gte(usdnProtocol.getHighestPopulatedTick(), states[1].highestActualTick, GLOB_01);
        }
    }

    function invariant_GLOB_02() internal {
        fl.neq(states[1].divisor, usdn.MIN_DIVISOR(), GLOB_02);
    }

    function invariant_GLOB_03() internal {
        if (lastFundingSwitch) {
            fl.neq(states[1].lastFunding, 0, GLOB_03);
        }
    }

    function invariant_GLOB_04() internal {
        if (states[1].pendingActionsLength > 0) {
            fl.gte(
                states[1].actorStates[address(usdnProtocol)].ethBalance,
                states[1].pendingActionsLength * states[1].securityDeposit,
                GLOB_04
            );
        }
    }

    function invariant_GLOB_05() internal {
        if (states[1].totalLongPositions > 0) {
            fl.gt(states[1].tradingExpo, 0, GLOB_05);
        }
    }

    function invariant_GLOB_06() internal {
        fl.eq(states[1].lowLeveragePositionsCount, 0, GLOB_06);
    }

    function invariant_GLOB_07() internal {
        int256 calculatedBalance = int256(states[1].vaultBalance) + int256(states[1].balanceLong)
            + int256(states[1].pendingProtocolFee) + states[1].pendingVaultBalance;

        int256 currentBalance = int256(states[1].actorStates[address(usdnProtocol)].wstETHBalance);

        // It is known that some rounding can perturb this accounting, if this would lead
        // to an underflow revert it will be caught by the error assertions.
        //
        // If the imprecision exceeds 100 wei flag it.
        fl.gte(currentBalance + 100, calculatedBalance, GLOB_07);
    }
}

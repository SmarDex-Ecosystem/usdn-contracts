// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.26;

import { PropertiesBase } from "./PropertiesBase.sol";

/**
 * @notice Withdrawal validation invariants
 * @dev Ensures accurate state transitions and payouts during withdrawal validation
 */
abstract contract Properties_WITHV is PropertiesBase {
    function invariant_WITHV_01(address user) internal {
        if (SINGLE_ACTOR_MODE == false) {
            // NOTE: unhandled security deposit case
        } else {
            fl.eq(
                states[1].actorStates[user].ethBalance,
                states[0].actorStates[user].ethBalance + uint256(states[1].securityDeposit) - pythPrice,
                WITHV_01
            );
        }
    }

    function invariant_WITHV_02(address user) internal {
        fl.gte(states[1].actorStates[user].wstETHBalance, states[0].actorStates[user].wstETHBalance, WITHV_02);
    }

    function invariant_WITHV_03() internal {
        if (SINGLE_ACTOR_MODE == false) {
            // NOTE: unhandled security deposit case
        } else {
            fl.eq(
                states[1].actorStates[address(usdnProtocol)].ethBalance,
                states[0].actorStates[address(usdnProtocol)].ethBalance - uint256(states[1].securityDeposit),
                WITHV_03
            );
        }
    }

    function invariant_WITHV_04(ValidateWithdrawalParams memory params) internal {
        fl.lte(
            states[1].actorStates[address(usdnProtocol)].usdnShares,
            uint256(int256(states[0].actorStates[address(usdnProtocol)].usdnShares) + int256(params.usdnPendingActions)),
            WITHV_04
        );
    }

    function invariant_WITHV_05() internal {
        fl.lte(
            states[1].actorStates[address(usdnProtocol)].wstETHBalance,
            states[0].actorStates[address(usdnProtocol)].wstETHBalance - states[1].withdrawAssetToTransferAfterFees,
            WITHV_05
        );
    }
}

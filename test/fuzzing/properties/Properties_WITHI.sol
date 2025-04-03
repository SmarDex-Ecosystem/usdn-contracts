// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.26;

import "./PropertiesBase.sol";

/**
 * @notice Withdrawal initiation invariants
 * @dev Checks that balances and protocol state change correctly during withdrawal initiation
 */
abstract contract Properties_WITHI is PropertiesBase {
    function invariant_WITHI_01(address user, bool initiatedWithdrawal) internal {
        if (SINGLE_ACTOR_MODE == false) {
            // NOTE: unhandled security deposit case
        } else {
            if (states[1].positionsLiquidatable || states[1].positionWasLiqidatedInTheMeanwhile) {
                if (initiatedWithdrawal) {
                    if (states[1].positionWasLiqidatedInTheMeanwhile) {
                        fl.eq(
                            states[1].actorStates[user].ethBalance,
                            states[0].actorStates[user].ethBalance - pythPrice,
                            WITHI_01
                        );
                    } else {
                        fl.eq(
                            states[1].actorStates[user].ethBalance,
                            states[0].actorStates[user].ethBalance - uint256(states[1].securityDeposit) - pythPrice,
                            WITHI_01
                        );
                    }
                } else {
                    fl.eq(
                        states[1].actorStates[user].ethBalance,
                        states[0].actorStates[user].ethBalance - pythPrice,
                        WITHI_01
                    );
                }
            } else {
                fl.eq(
                    states[1].actorStates[user].ethBalance,
                    states[0].actorStates[user].ethBalance - uint256(states[1].securityDeposit) - pythPrice,
                    WITHI_01
                );
            }
        }
    }

    function invariant_WITHI_02(address user, InitiateWithdrawalParams memory params) internal {
        eqWithToleranceWei(
            states[1].actorStates[user].usdnShares,
            states[0].actorStates[user].usdnShares - params.usdnShares,
            1,
            WITHI_02
        );
    }

    function invariant_WITHI_03(InitiateWithdrawalParams memory params, bool initiatedWithdrawal) internal {
        if (SINGLE_ACTOR_MODE == false) {
            // NOTE: unhandled security deposit case
        } else {
            if (states[1].positionsLiquidatable || states[1].positionWasLiqidatedInTheMeanwhile) {
                if (initiatedWithdrawal) {
                    if (states[1].positionWasLiqidatedInTheMeanwhile) {
                        fl.eq(
                            states[1].actorStates[address(usdnProtocol)].ethBalance,
                            states[0].actorStates[address(usdnProtocol)].ethBalance,
                            WITHI_03
                        );
                    } else {
                        fl.eq(
                            states[1].actorStates[address(usdnProtocol)].ethBalance,
                            states[0].actorStates[address(usdnProtocol)].ethBalance + uint256(states[1].securityDeposit),
                            WITHI_03
                        );
                    }
                } else {
                    fl.eq(
                        states[1].actorStates[address(usdnProtocol)].ethBalance,
                        states[0].actorStates[address(usdnProtocol)].ethBalance,
                        WITHI_03
                    );
                }
            } else {
                fl.eq(
                    states[1].actorStates[address(usdnProtocol)].ethBalance,
                    states[0].actorStates[address(usdnProtocol)].ethBalance + uint256(states[1].securityDeposit)
                        - params.lastAction.securityDepositValue,
                    WITHI_03
                );
            }
        }
    }

    function invariant_WITHI_04(InitiateWithdrawalParams memory params) internal {
        if (!states[0].otherUsersPendingActions) {
            fl.eq(
                states[1].actorStates[address(usdnProtocol)].usdnShares,
                uint256(
                    int256(states[0].actorStates[address(usdnProtocol)].usdnShares) + int256(uint256(params.usdnShares))
                        + params.usdnPendingActions
                ),
                WITHI_04
            );
        }
    }
}

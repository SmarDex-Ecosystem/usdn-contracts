// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

import { IUsdnProtocolTypes } from "../../../src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";

import { PropertiesBase } from "./PropertiesBase.sol";

abstract contract Properties_POSCLOSI is PropertiesBase {
    function invariant_POSCLOSI_01(address sender, IUsdnProtocolTypes.LongActionOutcome outcome) internal {
        if (SINGLE_ACTOR_MODE == false) {
            // NOTE: unhandled security deposit case
        } else {
            if (outcome == IUsdnProtocolTypes.LongActionOutcome.Liquidated) {
                fl.eq(
                    states[1].actorStates[sender].ethBalance,
                    states[0].actorStates[sender].ethBalance - pythPrice,
                    POSCLOSI_01
                );
            } else if (outcome == IUsdnProtocolTypes.LongActionOutcome.Processed) {
                fl.eq(
                    states[1].actorStates[sender].ethBalance,
                    states[0].actorStates[sender].ethBalance - uint256(states[1].securityDeposit) - pythPrice,
                    POSCLOSI_01
                );
            }
        }
    }

    function invariant_POSCLOSI_02(address user, IUsdnProtocolTypes.LongActionOutcome outcome) internal {
        if (outcome == IUsdnProtocolTypes.LongActionOutcome.Liquidated) {
            fl.eq(uint8(states[1].actorStates[user].pendingAction.action), uint8(0), POSCLOSI_02);
        } else if (outcome == IUsdnProtocolTypes.LongActionOutcome.Processed) {
            fl.eq(
                uint8(states[1].actorStates[user].pendingAction.action),
                uint8(IUsdnProtocolTypes.ProtocolAction.ValidateClosePosition),
                POSCLOSI_02
            );
        }
    }

    function invariant_POSCLOSI_03(IUsdnProtocolTypes.LongActionOutcome outcome) internal {
        if (SINGLE_ACTOR_MODE == false) {
            // NOTE: unhandled security deposit case
        } else {
            if (outcome == IUsdnProtocolTypes.LongActionOutcome.Liquidated) {
                fl.eq(
                    states[1].actorStates[address(usdnProtocol)].ethBalance,
                    states[0].actorStates[address(usdnProtocol)].ethBalance,
                    POSCLOSI_03
                );
            } else if (outcome == IUsdnProtocolTypes.LongActionOutcome.Processed) {
                fl.eq(
                    states[1].actorStates[address(usdnProtocol)].ethBalance,
                    states[0].actorStates[address(usdnProtocol)].ethBalance + uint256(states[1].securityDeposit),
                    POSCLOSI_03
                );
            }
        }
    }

    function invariant_POSCLOSI_04(
        address sender, //NOTE: Hardcoded position owner
        IUsdnProtocolTypes.LongActionOutcome outcome
    ) internal {
        if (outcome == IUsdnProtocolTypes.LongActionOutcome.Liquidated) {
            if (states[1].liquidator == sender) {
                fl.eq(
                    states[1].actorStates[sender].wstETHBalance,
                    states[0].actorStates[sender].wstETHBalance + states[1].liquidationRewards,
                    POSCLOSI_04
                );
            }
        } else if (outcome == IUsdnProtocolTypes.LongActionOutcome.Processed) {
            if (states[1].liquidablePositions || states[1].positionWasLiquidatedInTheMeanwhile) {
                if (states[1].liquidator == sender) {
                    fl.eq(
                        states[1].actorStates[sender].wstETHBalance,
                        states[0].actorStates[sender].wstETHBalance + states[1].liquidationRewards,
                        POSCLOSI_04
                    );
                }
            }
        }
    }

    function invariant_POSCLOSI_05(IUsdnProtocolTypes.LongActionOutcome) internal {
        if (!states[1].rebalancerTriggered) {
            if (states[1].feeCollectorCallbackTriggered) {
                if (states[1].liquidablePositions || states[1].positionWasLiquidatedInTheMeanwhile) {
                    fl.eq(
                        states[1].actorStates[address(usdnProtocol)].wstETHBalance,
                        states[0].actorStates[address(usdnProtocol)].wstETHBalance - states[1].addedFees
                            - states[1].liquidationRewards,
                        POSCLOSI_05
                    );
                } else {
                    fl.eq(
                        states[1].actorStates[address(usdnProtocol)].wstETHBalance,
                        states[0].actorStates[address(usdnProtocol)].wstETHBalance - states[1].addedFees,
                        POSCLOSI_05
                    );
                }
            } else if (states[1].liquidablePositions || states[1].positionWasLiquidatedInTheMeanwhile) {
                fl.eq(
                    states[1].actorStates[address(usdnProtocol)].wstETHBalance,
                    states[0].actorStates[address(usdnProtocol)].wstETHBalance - states[1].liquidationRewards,
                    POSCLOSI_05
                );
            } else {
                fl.eq(
                    states[1].actorStates[address(usdnProtocol)].wstETHBalance,
                    states[0].actorStates[address(usdnProtocol)].wstETHBalance,
                    POSCLOSI_05
                );
            }
        }
    }
}

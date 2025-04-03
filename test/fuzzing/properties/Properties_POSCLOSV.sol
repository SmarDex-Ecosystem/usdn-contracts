// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.26;

import "./PropertiesBase.sol";

/**
 * @notice Position close validation invariants
 * @dev Checks post-validation state after a position is closed, including liquidation side effects
 */
abstract contract Properties_POSCLOSV is PropertiesBase {
    function invariant_POSCLOSV_01(address sender, Types.LongActionOutcome outcome) internal {
        if (outcome == Types.LongActionOutcome.Processed) {
            if (SINGLE_ACTOR_MODE == false) {
                // NOTE: unhandled security deposit case
            } else {
                fl.eq(
                    states[1].actorStates[sender].ethBalance,
                    states[0].actorStates[sender].ethBalance + uint256(states[1].securityDeposit) - pythPrice,
                    POSCLOSV_01
                );
            }
        }
    }

    function invariant_POSCLOSV_02(Types.LongActionOutcome outcome) internal {
        if (outcome == Types.LongActionOutcome.Processed) {
            if (SINGLE_ACTOR_MODE == false) {
                // NOTE: unhandled security deposit case
            } else {
                fl.eq(
                    states[1].actorStates[address(usdnProtocol)].ethBalance,
                    states[0].actorStates[address(usdnProtocol)].ethBalance - uint256(states[1].securityDeposit),
                    POSCLOSV_02
                );
            }
        }
    }

    function invariant_POSCLOSV_03(ValidateClosePositionParams memory params, Types.LongActionOutcome outcome)
        internal
    {
        int256 baseWstETHBalance = int256(states[0].actorStates[address(usdnProtocol)].wstETHBalance);
        // int256 pendingActions = int256(params.wstethPendingActions);
        int256 positionProfit = int256(states[1].positionProfit);
        int256 newWstETHBalance = int256(states[1].actorStates[address(usdnProtocol)].wstETHBalance);
        if (outcome == Types.LongActionOutcome.Processed) {
            if (states[1].feeCollectorCallbackTriggered) {
                fl.eq(
                    newWstETHBalance,
                    baseWstETHBalance - int256(params.closeAmount) - positionProfit - int256(states[1].addedFees),
                    POSCLOSV_03
                );
            } else {
                fl.eq(newWstETHBalance, baseWstETHBalance - int256(params.closeAmount) - positionProfit, POSCLOSV_03);
            }
        }
    }

    function invariant_POSCLOSV_04(ValidateClosePositionParams memory params, Types.LongActionOutcome outcome)
        internal
    {
        if (outcome == Types.LongActionOutcome.Liquidated) {
            if (states[1].liquidator == params.validator) {
                if (states[1].feeCollectorCallbackTriggered) {
                    fl.gte(
                        states[1].actorStates[address(usdnProtocol)].wstETHBalance,
                        states[0].actorStates[address(usdnProtocol)].wstETHBalance - params.closeAmount
                            - params.wstethPendingActions - states[1].liquidationRewards - states[1].addedFees,
                        POSCLOSV_04
                    );
                } else {
                    fl.gte(
                        states[1].actorStates[address(usdnProtocol)].wstETHBalance,
                        states[0].actorStates[address(usdnProtocol)].wstETHBalance - params.closeAmount
                            - params.wstethPendingActions - states[1].liquidationRewards,
                        POSCLOSV_04
                    );
                }
            }
        } else if (outcome == Types.LongActionOutcome.Processed) {
            // Log all balance components for normal case

            if (states[1].feeCollectorCallbackTriggered) {
                if (states[1].positionsLiquidatable || states[1].positionWasLiqidatedInTheMeanwhile) {
                    fl.gte(
                        int256(states[1].actorStates[address(usdnProtocol)].wstETHBalance),
                        int256(states[0].actorStates[address(usdnProtocol)].wstETHBalance) - int256(params.closeAmount)
                            - int256(params.wstethPendingActions) - states[1].positionProfit - int256(states[1].addedFees)
                            - int256(states[1].liquidationRewards),
                        POSCLOSV_04
                    );
                } else {
                    fl.gte(
                        int256(states[1].actorStates[address(usdnProtocol)].wstETHBalance),
                        int256(states[0].actorStates[address(usdnProtocol)].wstETHBalance) - int256(params.closeAmount)
                            - int256(params.wstethPendingActions) - states[1].positionProfit - int256(states[1].addedFees),
                        POSCLOSV_04
                    );
                }
            } else {
                if (states[1].positionsLiquidatable || states[1].positionWasLiqidatedInTheMeanwhile) {
                    fl.gte(
                        int256(states[1].actorStates[address(usdnProtocol)].wstETHBalance),
                        int256(states[0].actorStates[address(usdnProtocol)].wstETHBalance) - int256(params.closeAmount)
                            - int256(params.wstethPendingActions) - states[1].positionProfit
                            - int256(states[1].liquidationRewards),
                        POSCLOSV_04
                    );
                } else {
                    fl.gte(
                        int256(states[1].actorStates[address(usdnProtocol)].wstETHBalance),
                        int256(states[0].actorStates[address(usdnProtocol)].wstETHBalance) - int256(params.closeAmount)
                            - int256(params.wstethPendingActions) - states[1].positionProfit,
                        POSCLOSV_04
                    );
                }
            }
        }
    }

    function invariant_POSCLOSV_05(
        address user,
        ValidateClosePositionParams memory params,
        Types.LongActionOutcome outcome
    ) internal {
        if (outcome == Types.LongActionOutcome.Liquidated) {
            if (states[1].liquidator == params.validator) {
                fl.lte(
                    states[1].actorStates[user].wstETHBalance,
                    uint256(
                        int256(states[0].actorStates[user].wstETHBalance) + int256(params.closeAmount)
                            + int256(states[1].liquidationRewards) + states[1].positionProfit
                    ),
                    POSCLOSV_05
                );
            }
        } else if (outcome == Types.LongActionOutcome.Processed) {
            fl.lte(
                states[1].actorStates[user].wstETHBalance,
                uint256(
                    int256(states[0].actorStates[user].wstETHBalance) + int256(params.closeAmount)
                        + states[1].positionProfit
                ),
                POSCLOSV_05
            );
        }
    }

    //NOTE: by this implementation, repeats POSCLOSV_05
    function invariant_POSCLOSV_06(
        address user,
        ValidateClosePositionParams memory params,
        Types.LongActionOutcome outcome
    ) internal {
        if (outcome == Types.LongActionOutcome.Processed) {
            fl.eq(
                states[1].actorStates[user].wstETHBalance,
                uint256(
                    int256(states[0].actorStates[user].wstETHBalance) + int256(params.closeAmount)
                        + states[1].positionProfit
                ),
                POSCLOSV_06
            );
        }
    }

    function invariant_POSCLOSV_07(address validator, address caller, Types.LongActionOutcome outcome) internal {
        if (outcome == Types.LongActionOutcome.Processed) {
            if (caller != validator) {
                fl.eq(
                    states[1].actorStates[validator].ethBalance,
                    states[0].actorStates[validator].ethBalance,
                    POSCLOSV_07
                );
            }
        }
    }

    function invariant_POSCLOSV_08(address user, address caller, Types.LongActionOutcome outcome) internal {
        if (outcome == Types.LongActionOutcome.Processed) {
            if (caller != user) {
                fl.eq(
                    states[1].actorStates[caller].wstETHBalance,
                    states[0].actorStates[caller].wstETHBalance,
                    POSCLOSV_08
                );
            }
        }
    }

    function invariant_POSCLOSV_09(address user, address validator, Types.LongActionOutcome outcome) internal {
        if (outcome == Types.LongActionOutcome.Processed) {
            if (validator != user) {
                fl.eq(states[1].actorStates[user].ethBalance, states[0].actorStates[user].ethBalance, POSCLOSV_09);
            }
        }
    }

    function invariant_POSCLOSV_10(address user, address validator, Types.LongActionOutcome outcome) internal {
        if (outcome == Types.LongActionOutcome.Processed) {
            if (validator != user) {
                fl.eq(
                    states[1].actorStates[validator].wstETHBalance,
                    states[0].actorStates[validator].wstETHBalance,
                    POSCLOSV_10
                );
            }
        }
    }
}

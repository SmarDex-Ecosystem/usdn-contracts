// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

import { PropertiesBase } from "./PropertiesBase.sol";

abstract contract Properties_DEPV is PropertiesBase {
    function invariant_DEPV_01(address user) internal {
        fl.gt(states[1].actorStates[user].usdnShares, states[0].actorStates[user].usdnShares, DEPV_01);
    }

    function invariant_DEPV_02(address user, address caller) internal {
        if (user != caller) {
            fl.eq(states[0].actorStates[caller].usdnShares, states[1].actorStates[caller].usdnShares, DEPV_02);
        }
    }

    function invariant_DEPV_03(address user, address validator) internal {
        if (user != validator) {
            fl.eq(states[0].actorStates[validator].usdnShares, states[1].actorStates[validator].usdnShares, DEPV_03);
        }
    }

    function invariant_DEPV_04(address user, address validator) internal {
        if (SINGLE_ACTOR_MODE == false) {
            // NOTE: unhandled security deposit case
        } else {
            if (user != validator) {
                fl.eq(
                    states[1].actorStates[user].ethBalance,
                    states[0].actorStates[user].ethBalance + uint256(states[1].securityDeposit),
                    DEPV_04
                );
            } else {
                fl.eq(
                    states[1].actorStates[user].ethBalance,
                    states[0].actorStates[user].ethBalance + uint256(states[1].securityDeposit) - pythPrice, //user paid
                        // for its price validation
                    DEPV_04
                );
            }
        }
    }

    function invariant_DEPV_05(ValidateDepositParams memory params) internal {
        uint256 expectedUsdn = calculateUsdnOnDeposit(params.wstethPendingActions, params.pendingAction);

        eqWithToleranceWei(
            states[1].usdnTotalSupply,
            states[0].usdnTotalSupply + expectedUsdn,
            1, //tolerance
            DEPV_05
        );
    }

    function invariant_DEPV_06(address caller) internal {
        if (states[1].liquidablePositions || states[1].positionWasLiquidatedInTheMeanwhile) {
            if (states[1].liquidator == caller) {
                fl.eq(
                    states[1].actorStates[caller].wstETHBalance,
                    states[0].actorStates[caller].wstETHBalance + states[1].liquidationRewards,
                    DEPV_06
                );
            } else {
                fl.eq(states[1].actorStates[caller].wstETHBalance, states[0].actorStates[caller].wstETHBalance, DEPV_06);
            }
        }
    }

    function invariant_DEPV_07(ValidateDepositParams memory params) internal {
        if (!states[1].rebalancerTriggered) {
            if (states[1].feeCollectorCallbackTriggered) {
                if (states[1].liquidablePositions || states[1].positionWasLiquidatedInTheMeanwhile) {
                    if (states[1].liquidator == params.validator) {
                        fl.eq(
                            states[1].actorStates[address(usdnProtocol)].wstETHBalance,
                            states[0].actorStates[address(usdnProtocol)].wstETHBalance - params.wstethPendingActions
                                - states[1].addedFees - states[1].liquidationRewards,
                            DEPV_07
                        );
                    } else {
                        fl.eq(
                            states[1].actorStates[address(usdnProtocol)].wstETHBalance,
                            states[0].actorStates[address(usdnProtocol)].wstETHBalance - params.wstethPendingActions
                                - states[1].addedFees,
                            DEPV_07
                        );
                    }
                } else {
                    fl.eq(
                        states[1].actorStates[address(usdnProtocol)].wstETHBalance,
                        states[0].actorStates[address(usdnProtocol)].wstETHBalance - params.wstethPendingActions
                            - states[1].addedFees,
                        DEPV_07
                    );
                }
            } else if (states[1].liquidablePositions || states[1].positionWasLiquidatedInTheMeanwhile) {
                if (states[1].liquidator == params.validator) {
                    fl.eq(
                        states[1].actorStates[address(usdnProtocol)].wstETHBalance,
                        states[0].actorStates[address(usdnProtocol)].wstETHBalance - params.wstethPendingActions
                            - states[1].liquidationRewards,
                        DEPV_07
                    );
                } else {
                    fl.eq(
                        states[1].actorStates[address(usdnProtocol)].wstETHBalance,
                        states[0].actorStates[address(usdnProtocol)].wstETHBalance - params.wstethPendingActions,
                        DEPV_07
                    );
                }
            } else {
                fl.eq(
                    states[1].actorStates[address(usdnProtocol)].wstETHBalance,
                    states[0].actorStates[address(usdnProtocol)].wstETHBalance - params.wstethPendingActions,
                    DEPV_07
                );
            }
        }
    }

    function invariant_DEPV_08(address validator) internal {
        if (states[1].liquidablePositions || states[1].positionWasLiquidatedInTheMeanwhile) {
            if (states[1].liquidator != validator) {
                fl.eq(
                    states[0].actorStates[validator].wstETHBalance,
                    states[1].actorStates[validator].wstETHBalance,
                    DEPV_08
                );
            }
        }
        if (states[1].feeCollectorCallbackTriggered) {
            if (currentActor != validator) {
                fl.eq(
                    states[0].actorStates[validator].wstETHBalance,
                    states[1].actorStates[validator].wstETHBalance,
                    DEPV_08
                );
            }
        }
    }

    function invariant_DEPV_09(address user) internal {
        if (states[1].liquidablePositions || states[1].positionWasLiquidatedInTheMeanwhile) {
            if (states[1].liquidator != user) {
                fl.eq(states[0].actorStates[user].wstETHBalance, states[1].actorStates[user].wstETHBalance, DEPV_09);
            }
        }
        if (states[1].feeCollectorCallbackTriggered) {
            if (currentActor != user) {
                fl.eq(states[0].actorStates[user].wstETHBalance, states[1].actorStates[user].wstETHBalance, DEPV_09);
            }
        }
    }
}

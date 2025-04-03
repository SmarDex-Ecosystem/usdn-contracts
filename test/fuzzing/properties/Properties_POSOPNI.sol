// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.26;

import "./PropertiesBase.sol";

/**
 * @notice Position open initiation invariants
 * @dev Verifies correct balance and state updates when opening a leveraged position
 */
abstract contract Properties_POSOPNI is PropertiesBase {
    function invariant_POSOPNI_01(InitiateOpenPositionParams memory params, bool initiatedOpen) internal {
        if (SINGLE_ACTOR_MODE == false) {
            // NOTE: unhandled security deposit case
        } else {
            if (states[1].positionsLiquidatable || states[1].positionWasLiqidatedInTheMeanwhile) {
                /*
                 * If ticks liquidated is not users position ticks, meaning we liquidated
                 * some other positions and our security deposit stays in the protocol
                 */
                if (initiatedOpen) {
                    if (states[1].positionWasLiqidatedInTheMeanwhile) {
                        fl.eq(
                            states[1].actorStates[address(usdnProtocol)].ethBalance,
                            states[0].actorStates[address(usdnProtocol)].ethBalance,
                            POSOPNI_01
                        );
                    } else {
                        fl.eq(
                            states[1].actorStates[address(usdnProtocol)].ethBalance,
                            states[0].actorStates[address(usdnProtocol)].ethBalance + uint256(states[1].securityDeposit),
                            POSOPNI_01
                        );
                    }
                } else {
                    fl.eq(
                        states[1].actorStates[address(usdnProtocol)].ethBalance,
                        states[0].actorStates[address(usdnProtocol)].ethBalance - params.lastAction.securityDepositValue,
                        POSOPNI_01
                    );
                }
            } else {
                fl.eq(
                    states[1].actorStates[address(usdnProtocol)].ethBalance,
                    states[0].actorStates[address(usdnProtocol)].ethBalance + uint256(states[1].securityDeposit)
                        - params.lastAction.securityDepositValue,
                    POSOPNI_01
                );
            }
        }
    }

    function invariant_POSOPNI_02(address user, InitiateOpenPositionParams memory params, bool initiatedOpen)
        internal
    {
        if (SINGLE_ACTOR_MODE == false) {
            // NOTE: unhandled security deposit case
        } else {
            if (states[1].positionsLiquidatable || states[1].positionWasLiqidatedInTheMeanwhile) {
                if (initiatedOpen) {
                    if (states[1].positionWasLiqidatedInTheMeanwhile) {
                        fl.eq(
                            states[1].actorStates[address(user)].ethBalance,
                            states[0].actorStates[address(user)].ethBalance - pythPrice,
                            POSOPNI_02
                        );
                    } else {
                        fl.eq(
                            states[1].actorStates[address(user)].ethBalance,
                            states[0].actorStates[address(user)].ethBalance - uint256(states[1].securityDeposit)
                                + params.lastAction.securityDepositValue - pythPrice,
                            POSOPNI_02
                        );
                    }
                } else {
                    fl.eq(
                        states[1].actorStates[user].ethBalance,
                        states[0].actorStates[user].ethBalance - pythPrice,
                        POSOPNI_02
                    );
                }
            } else {
                fl.eq(
                    states[1].actorStates[user].ethBalance,
                    states[0].actorStates[user].ethBalance - uint256(states[1].securityDeposit)
                        + params.lastAction.securityDepositValue - pythPrice,
                    POSOPNI_02
                );
            }
        }
    }

    function invariant_POSOPNI_03(InitiateOpenPositionParams memory params) internal {
        if (!states[1].rebalancerTriggered) {
            if (states[1].feeCollectorCallbackTriggered) {
                if (states[1].positionsLiquidatable || states[1].positionWasLiqidatedInTheMeanwhile) {
                    fl.eq(
                        int256(states[1].actorStates[address(usdnProtocol)].wstETHBalance),
                        int256(states[0].actorStates[address(usdnProtocol)].wstETHBalance)
                            + int256(int128(params.amount)) - int256(params.wstethPendingActions)
                            - int256(states[1].addedFees) - int256(states[1].liquidationRewards)
                            - int256(states[1].positionProfit),
                        POSOPNI_03
                    );
                } else {
                    fl.eq(
                        int256(states[1].actorStates[address(usdnProtocol)].wstETHBalance),
                        int256(states[0].actorStates[address(usdnProtocol)].wstETHBalance)
                            + int256(int128(params.amount)) - int256(params.wstethPendingActions)
                            - int256(states[1].addedFees) - int256(states[1].liquidationRewards)
                            - int256(states[1].positionProfit),
                        POSOPNI_03
                    );
                }
            } else if (states[1].positionsLiquidatable || states[1].positionWasLiqidatedInTheMeanwhile) {
                uint256 pendingActionValue = params.wstethPendingActions;

                if (params.lastAction.action == Types.ProtocolAction.ValidateClosePosition) {
                    uint256 currentPrice = (createProtocolPrice() * wstETH.stEthPerToken()) / 1e18;

                    uint128 liqPrice = Utils._getEffectivePriceForTick(
                        params.lastAction.var1, // var1 is the tick for validateClose actions
                        params.lastAction.var6 // var6 is the liqMultiplier for validateClose actions
                    );

                    if (liqPrice > currentPrice) {
                        pendingActionValue = 0;
                    }
                }

                fl.eq(
                    int256(states[1].actorStates[address(usdnProtocol)].wstETHBalance),
                    int256(states[0].actorStates[address(usdnProtocol)].wstETHBalance) + int256(int128(params.amount))
                        - int256(pendingActionValue) - int256(states[1].liquidationRewards)
                        - int256(states[1].positionProfit),
                    POSOPNI_03
                );
            } else {
                if (
                    int256(states[1].actorStates[address(usdnProtocol)].wstETHBalance)
                        != int256(states[0].actorStates[address(usdnProtocol)].wstETHBalance)
                            + int256(int128(params.amount)) - int256(params.wstethPendingActions)
                            - int256(states[1].positionProfit)
                ) {
                    //NOTE: case 2
                } else {
                    fl.eq(
                        int256(states[1].actorStates[address(usdnProtocol)].wstETHBalance),
                        int256(states[0].actorStates[address(usdnProtocol)].wstETHBalance)
                            + int256(int128(params.amount)) - int256(params.wstethPendingActions)
                            - int256(states[1].positionProfit),
                        POSOPNI_03
                    );
                }
            }
        }
    }

    function invariant_POSOPNI_04(address user, InitiateOpenPositionParams memory params) internal {
        if (!states[1].rebalancerTriggered) {
            if (states[1].positionsLiquidatable || states[1].positionWasLiqidatedInTheMeanwhile) {
                if (states[1].liquidator == user) {
                    fl.eq(
                        int256(states[1].actorStates[user].wstETHBalance),
                        int256(states[0].actorStates[user].wstETHBalance) - int256(int128(params.amount))
                            + int256(states[1].liquidationRewards) + int256(states[1].positionProfit),
                        POSOPNI_04
                    );
                } else {
                    fl.eq(
                        int256(states[1].actorStates[user].wstETHBalance),
                        int256(states[0].actorStates[user].wstETHBalance) - int256(int128(params.amount))
                            + int256(states[1].positionProfit),
                        POSOPNI_04
                    );
                }
            } else {
                if (user == params.lastAction.to) {
                    fl.eq(
                        int256(states[1].actorStates[user].wstETHBalance),
                        int256(states[0].actorStates[user].wstETHBalance) - int256(int128(params.amount))
                            + int256(states[1].positionProfit) + int256(params.wstethPendingActions),
                        POSOPNI_04
                    );
                } else {
                    fl.eq(
                        int256(states[1].actorStates[user].wstETHBalance),
                        int256(states[0].actorStates[user].wstETHBalance) - int256(int128(params.amount)),
                        POSOPNI_04
                    );
                }
            }
        }
    }
}

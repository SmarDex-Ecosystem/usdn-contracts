// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.26;

import "./PropertiesBase.sol";

/**
 * @notice Deposit-related invariants for the USDN protocol
 * @dev Contains property-based tests focused on deposit behavior and constraints
 */
abstract contract Properties_DEPI is PropertiesBase {
    function invariant_DEPI_01(address user, bool initiatedDeposit) internal {
        if (SINGLE_ACTOR_MODE == false) {
            // NOTE: unhandled security deposit case
        } else {
            if (states[1].positionsLiquidatable || states[1].positionWasLiqidatedInTheMeanwhile) {
                if (initiatedDeposit) {
                    if (states[1].positionWasLiqidatedInTheMeanwhile) {
                        fl.eq(
                            states[1].actorStates[user].ethBalance,
                            states[0].actorStates[user].ethBalance - pythPrice,
                            DEPI_01
                        );
                    } else {
                        fl.eq(
                            states[1].actorStates[user].ethBalance,
                            states[0].actorStates[user].ethBalance - uint256(states[1].securityDeposit) - pythPrice,
                            DEPI_01
                        );
                    }
                } else {
                    fl.eq(
                        states[1].actorStates[user].ethBalance,
                        states[0].actorStates[user].ethBalance - pythPrice,
                        DEPI_01
                    );
                }
            } else {
                fl.eq(
                    states[1].actorStates[user].ethBalance,
                    states[0].actorStates[user].ethBalance - uint256(states[1].securityDeposit) - pythPrice,
                    DEPI_01
                );
            }
        }
    }

    function invariant_DEPI_02(address user, InitiateDepositParams memory params) internal {
        if (!states[1].rebalancerTriggered) {
            if (states[1].positionsLiquidatable || states[1].positionWasLiqidatedInTheMeanwhile) {
                if (states[1].liquidator == params.validator) {
                    fl.eq(
                        uint256(int256(states[1].actorStates[user].wstETHBalance)),
                        uint256(
                            int256(states[0].actorStates[user].wstETHBalance) - int256(int128(params.wstEthAmount))
                                + int256(states[1].liquidationRewards) + states[1].positionProfit
                        ),
                        DEPI_02
                    );
                }
            } else {
                fl.eq(
                    uint256(int256(states[1].actorStates[user].wstETHBalance)),
                    uint256(
                        int256(states[0].actorStates[user].wstETHBalance) - int256(int128(params.wstEthAmount))
                            + states[1].positionProfit
                    ),
                    DEPI_02
                );
            }
        }
    }

    function invariant_DEPI_03(address user) internal {
        fl.lt(states[1].actorStates[user].sdexBalance, states[0].actorStates[user].sdexBalance, DEPI_03);
    }

    function invariant_DEPI_04(InitiateDepositParams memory params, bool initiatedDeposit) internal {
        if (SINGLE_ACTOR_MODE == false) {
            // NOTE: unhandled security deposit case
        } else {
            if (states[1].positionsLiquidatable || states[1].positionWasLiqidatedInTheMeanwhile) {
                if (initiatedDeposit) {
                    if (states[1].positionWasLiqidatedInTheMeanwhile) {
                        fl.eq(
                            states[1].actorStates[address(usdnProtocol)].ethBalance,
                            states[0].actorStates[address(usdnProtocol)].ethBalance,
                            DEPI_04
                        );
                    } else {
                        fl.eq(
                            states[1].actorStates[address(usdnProtocol)].ethBalance,
                            states[0].actorStates[address(usdnProtocol)].ethBalance + uint256(states[1].securityDeposit),
                            DEPI_04
                        );
                    }
                } else {
                    fl.eq(
                        states[1].actorStates[address(usdnProtocol)].ethBalance,
                        states[0].actorStates[address(usdnProtocol)].ethBalance,
                        DEPI_04
                    );
                }
            } else {
                fl.eq(
                    states[1].actorStates[address(usdnProtocol)].ethBalance,
                    states[0].actorStates[address(usdnProtocol)].ethBalance + uint256(states[1].securityDeposit)
                        - params.lastAction.securityDepositValue,
                    DEPI_04
                );
            }
        }
    }

    function invariant_DEPI_05(InitiateDepositParams memory params) internal {
        if (!states[1].rebalancerTriggered) {
            if (states[1].feeCollectorCallbackTriggered) {
                if (states[1].positionsLiquidatable || states[1].positionWasLiqidatedInTheMeanwhile) {
                    fl.eq(
                        int256(states[1].actorStates[address(usdnProtocol)].wstETHBalance),
                        int256(states[0].actorStates[address(usdnProtocol)].wstETHBalance)
                            + int256(int128(params.wstEthAmount)) - int256(params.wstethPendingActions)
                            - int256(states[1].addedFees) - int256(states[1].liquidationRewards) - states[1].positionProfit,
                        DEPI_05
                    );
                } else {
                    fl.eq(
                        int256(states[1].actorStates[address(usdnProtocol)].wstETHBalance),
                        int256(states[0].actorStates[address(usdnProtocol)].wstETHBalance)
                            + int256(int128(params.wstEthAmount)) - int256(params.wstethPendingActions)
                            - int256(states[1].addedFees) - states[1].positionProfit,
                        DEPI_05
                    );
                }
            } else if (states[1].positionsLiquidatable || states[1].positionWasLiqidatedInTheMeanwhile) {
                fl.eq(
                    int256(states[1].actorStates[address(usdnProtocol)].wstETHBalance),
                    int256(states[0].actorStates[address(usdnProtocol)].wstETHBalance)
                        + int256(int128(params.wstEthAmount)) - int256(params.wstethPendingActions)
                        - int256(states[1].liquidationRewards) - states[1].positionProfit,
                    DEPI_05
                );
            } else {
                fl.eq(
                    int256(states[1].actorStates[address(usdnProtocol)].wstETHBalance),
                    int256(states[0].actorStates[address(usdnProtocol)].wstETHBalance)
                        + int256(int128(params.wstEthAmount)) - int256(params.wstethPendingActions)
                        - states[1].positionProfit,
                    DEPI_05
                );
            }
        }
    }
}

// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.26;

import { PropertiesBase } from "./PropertiesBase.sol";

import { IUsdnProtocolTypes as Types } from "../../../src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";

/**
 * @notice Position open validation invariants
 * @dev Ensures correct asset movement and protocol adjustments after position is validated
 */
abstract contract Properties_POSOPNV is PropertiesBase {
    // @todo user is not used?
    function invariant_POSOPNV_01(
        address user,
        address validator,
        ValidateOpenPositionParams memory params,
        Types.LongActionOutcome outcome
    ) internal {
        if (outcome == Types.LongActionOutcome.Processed) {
            if (SINGLE_ACTOR_MODE == false) {
                // NOTE: unhandled security deposit case
            } else {
                fl.eq(
                    states[1].actorStates[validator].ethBalance,
                    states[0].actorStates[validator].ethBalance + uint256(states[1].securityDeposit)
                        + params.lastAction.securityDepositValue - pythPrice,
                    POSOPNV_01
                );
            }
        }
    }

    function invariant_POSOPNV_02(ValidateOpenPositionParams memory params, Types.LongActionOutcome outcome) internal {
        if (outcome == Types.LongActionOutcome.Processed) {
            if (SINGLE_ACTOR_MODE == false) {
                // NOTE: unhandled security deposit case
            } else {
                if (
                    states[1].actorStates[address(usdnProtocol)].ethBalance
                        == states[0].actorStates[address(usdnProtocol)].ethBalance
                        || states[1].actorStates[address(usdnProtocol)].ethBalance
                            == states[0].actorStates[address(usdnProtocol)].ethBalance - uint256(states[1].securityDeposit)
                ) {
                    //NOTE: unhandled case
                } else {
                    fl.eq(
                        states[1].actorStates[address(usdnProtocol)].ethBalance,
                        states[0].actorStates[address(usdnProtocol)].ethBalance - uint256(states[1].securityDeposit)
                            - params.lastAction.securityDepositValue,
                        POSOPNV_02
                    );
                }
            }
        }
    }

    function invariant_POSOPNV_03(ValidateOpenPositionParams memory params, Types.LongActionOutcome outcome) internal {
        if (states[1].feeCollectorCallbackTriggered) {
            if (outcome == Types.LongActionOutcome.Liquidated) {
                if (states[1].liquidator == params.validator) {
                    fl.eq(
                        int256(states[1].actorStates[address(usdnProtocol)].wstETHBalance),
                        int256(states[0].actorStates[address(usdnProtocol)].wstETHBalance)
                            - int256(params.wstethPendingActions) - int256(states[1].addedFees)
                            - int256(states[1].liquidationRewards) - int256(states[1].positionProfit),
                        POSOPNV_03
                    );
                } else {
                    fl.eq(
                        int256(states[1].actorStates[address(usdnProtocol)].wstETHBalance),
                        int256(states[0].actorStates[address(usdnProtocol)].wstETHBalance)
                            - int256(params.wstethPendingActions) - int256(states[1].addedFees)
                            - int256(states[1].positionProfit),
                        POSOPNV_03
                    );
                }
            } else if (outcome == Types.LongActionOutcome.Processed) {
                fl.eq(
                    int256(states[1].actorStates[address(usdnProtocol)].wstETHBalance),
                    int256(states[0].actorStates[address(usdnProtocol)].wstETHBalance)
                        - int256(params.wstethPendingActions) - int256(states[1].addedFees)
                        - int256(states[1].positionProfit),
                    POSOPNV_03
                );
            }
        } else {
            if (outcome == Types.LongActionOutcome.Liquidated) {
                if (states[1].liquidator == params.validator) {
                    fl.eq(
                        int256(states[1].actorStates[address(usdnProtocol)].wstETHBalance),
                        int256(states[0].actorStates[address(usdnProtocol)].wstETHBalance)
                            - int256(params.wstethPendingActions) - int256(states[1].liquidationRewards)
                            - int256(states[1].positionProfit),
                        POSOPNV_03
                    );
                } else {
                    fl.eq(
                        int256(states[1].actorStates[address(usdnProtocol)].wstETHBalance),
                        int256(states[0].actorStates[address(usdnProtocol)].wstETHBalance)
                            - int256(params.wstethPendingActions) - int256(states[1].positionProfit),
                        POSOPNV_03
                    );
                }
            } else if (outcome == Types.LongActionOutcome.Processed) {
                fl.eq(
                    int256(states[1].actorStates[address(usdnProtocol)].wstETHBalance),
                    int256(states[0].actorStates[address(usdnProtocol)].wstETHBalance)
                        - int256(params.wstethPendingActions) - int256(states[1].positionProfit),
                    POSOPNV_03
                );
            }
        }
    }

    function invariant_POSOPNV_04(address sender, Types.LongActionOutcome outcome) internal {
        if (outcome != Types.LongActionOutcome.Liquidated) {
            if (states[1].liquidator == sender) {
                fl.eq(
                    states[1].actorStates[sender].wstETHBalance,
                    states[0].actorStates[sender].wstETHBalance + states[1].liquidationRewards,
                    POSOPNV_04
                );
            }
        } else if (outcome == Types.LongActionOutcome.Processed) {
            fl.eq(states[1].actorStates[sender].wstETHBalance, states[0].actorStates[sender].wstETHBalance, POSOPNV_04);
        }
    }
}

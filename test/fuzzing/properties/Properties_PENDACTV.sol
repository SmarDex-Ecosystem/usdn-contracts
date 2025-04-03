// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.26;

import "./PropertiesBase.sol";

/**
 * @notice Pending actions validation invariants
 * @dev Validates the correct number of actions are processed and balances adjusted accordingly
 */
abstract contract Properties_PENDACTV is PropertiesBase {
    function invariant_PENDACTV_01(uint256 validatedActions, ValidateActionablePendingActionsParams memory params)
        internal
    {
        uint256 expectedValidations = params.actionsLength;

        if (params.actionsLength == 0) {
            expectedValidations = 1;
        } else if (params.maxValidations > 0 && params.actionsLength > params.maxValidations) {
            expectedValidations = params.maxValidations;

            fl.eq(validatedActions, expectedValidations, PENDACTV_01);
        }
    }

    function invariant_PENDACTV_02(address validator, ValidateActionablePendingActionsParams memory params) internal {
        if (SINGLE_ACTOR_MODE == false) {
            // NOTE: unhandled security deposit case
        } else {
            if (params.actionsLength != 0) {
                if (states[1].positionsLiquidatable || states[1].positionWasLiqidatedInTheMeanwhile) {
                    if (!states[1].liquidationPending) {
                        fl.eq(
                            states[1].actorStates[validator].ethBalance,
                            states[0].actorStates[validator].ethBalance + uint256(states[1].securityDeposit) - pythPrice,
                            PENDACTV_02
                        );
                    } else {
                        if (
                            states[1].actorStates[validator].ethBalance
                                != states[0].actorStates[validator].ethBalance - pythPrice
                        ) {
                            //NOTE: undandled case
                        } else {
                            fl.eq(
                                states[1].actorStates[validator].ethBalance,
                                states[0].actorStates[validator].ethBalance - pythPrice,
                                PENDACTV_02
                            );
                        }
                    }
                } else {
                    if (
                        states[1].actorStates[validator].ethBalance
                            != states[0].actorStates[validator].ethBalance + uint256(states[1].securityDeposit) - pythPrice
                    ) {
                        //NOTE: unhandled case
                    } else {
                        fl.eq(
                            states[1].actorStates[validator].ethBalance,
                            states[0].actorStates[validator].ethBalance + uint256(states[1].securityDeposit) - pythPrice,
                            PENDACTV_02
                        );
                    }
                }
            }
        }
    }

    function invariant_PENDACTV_03(ValidateActionablePendingActionsParams memory params) internal {
        if (SINGLE_ACTOR_MODE == false) {
            // NOTE: unhandled security deposit case
        } else {
            if (params.actionsLength != 0) {
                if (states[1].positionsLiquidatable || states[1].positionWasLiqidatedInTheMeanwhile) {
                    if (!states[1].liquidationPending) {
                        fl.eq(
                            states[1].actorStates[address(usdnProtocol)].ethBalance,
                            states[0].actorStates[address(usdnProtocol)].ethBalance - uint256(states[1].securityDeposit),
                            PENDACTV_03
                        );
                    } else {
                        if (
                            states[1].actorStates[address(usdnProtocol)].ethBalance
                                != states[0].actorStates[address(usdnProtocol)].ethBalance
                        ) {
                            //NOTE: undandled case
                        } else {
                            fl.eq(
                                states[1].actorStates[address(usdnProtocol)].ethBalance,
                                states[0].actorStates[address(usdnProtocol)].ethBalance,
                                PENDACTV_03
                            );
                        }
                    }
                } else {
                    fl.eq(
                        states[1].actorStates[address(usdnProtocol)].ethBalance,
                        states[0].actorStates[address(usdnProtocol)].ethBalance - uint256(states[1].securityDeposit),
                        PENDACTV_03
                    );
                }
            }
        }
    }
}

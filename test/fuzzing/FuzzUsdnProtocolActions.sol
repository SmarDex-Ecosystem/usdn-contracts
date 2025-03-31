// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

import "./FuzzAdmin.sol";
import "./helper/postconditions/PostconditionsUsdnProtocolActions.sol";
import "./helper/preconditions/PreconditionsUsdnProtocolActions.sol";

contract FuzzUsdnProtocolActions is PreconditionsUsdnProtocolActions, PostconditionsUsdnProtocolActions, FuzzAdmin {
    function fuzz_initiateOpenPosition(uint256 amountSeed, uint256 leverageSeed)
        public
        setCurrentActor
        enforceOneActionPerCall
    {
        fuzz_setPrice(0); //here we are just updating oracle timestamp with the same price we already have

        InitiateOpenPositionParams memory params = initiateOpenPositionPrecondtions(amountSeed, leverageSeed);

        address[] memory actorsToUpdate = new address[](2);
        actorsToUpdate[0] = params.to;
        actorsToUpdate[1] = params.validator; //NOTE: currently the same addresses

        _before(actorsToUpdate);

        (bool success, bytes memory returnData) = _initiateOpenPositionCall(
            params.amount,
            params.desiredLiqPrice,
            type(uint128).max, //userMaxPrice
            params.userMaxLeverage,
            params.to,
            params.validator,
            type(uint256).max,
            createPythData(),
            params.previousActionsData,
            params.txValue
        );

        initiateOpenPositionPostconditions(success, returnData, actorsToUpdate, params, currentActor);
    }

    function fuzz_validateOpenPosition() public setCurrentActor enforceOneActionPerCall {
        ValidateOpenPositionParams memory params = validateOpenPositionPreconditions();

        fuzz_setPrice(0); //here we are just updating oracle timestamp with the same price we already have

        address[] memory actorsToUpdate = new address[](2);
        actorsToUpdate[0] = params.pendingAction.to;
        actorsToUpdate[1] = params.validator; //NOTE: currently the same addresses

        _before(actorsToUpdate);

        (bool success, bytes memory returnData) =
            _validateOpenPositionCall(params.validator, createPythData(), params.previousActionsData, params.txValue);

        validateOpenPositionPostconditions(success, returnData, actorsToUpdate, params);
    }

    function fuzz_initiateClosePosition(uint256 amountSeed, bool closeFull)
        public
        setCurrentActor
        enforceOneActionPerCall
    {
        InitiateClosePositionParams memory params = InitiateClosePositionPreconditions(amountSeed, closeFull); //prank         //
            // inside :)

        // SKIP if no work to do
        if (params.amountToClose == 0) {
            emit log("Skipping: amountToClose or positionId is zero.");
            return;
        }

        fuzz_setPrice(0); //here we are just updating oracle timestamp with the same price we already have

        address[] memory actorsToUpdate = new address[](1);
        actorsToUpdate[0] = params.validator; //NOTE: currently the same addresses

        _before(actorsToUpdate);

        (bool success, bytes memory returnData) = _initiateClosePositionCall(
            params.positionId,
            params.amountToClose,
            0, //userMinPrice
            params.to,
            params.validator,
            type(uint256).max, //deadline
            createPythData(),
            EMPTY_PREVIOUS_DATA,
            params.txValue
        );

        initiateClosePositionPostconditions(success, returnData, actorsToUpdate, params);
    }

    function fuzz_validateClosePosition() public setCurrentActor enforceOneActionPerCall {
        ValidateClosePositionParams memory params = validateClosePositionPreconditions();
        fuzz_setPrice(0); //here we are just updating oracle timestamp with the same price we already have

        address[] memory actorsToUpdate = new address[](3);

        actorsToUpdate[0] = params.user;
        actorsToUpdate[1] = params.validator;
        actorsToUpdate[2] = currentActor;

        _before(actorsToUpdate);

        (bool success, bytes memory returnData) =
            _validateClosePositionCall(params.validator, createPythData(), params.previousActionsData, params.txValue);

        validateClosePositionPostconditions(success, returnData, actorsToUpdate, params);
    }

    function fuzz_validateActionablePendingActions(uint256 maxValidations) public setCurrentActor {
        ValidateActionablePendingActionsParams memory params =
            validateActionablePendingActionsPreconditions(maxValidations);
        fuzz_setPrice(0); //here we are just updating oracle timestamp with the same price we already have

        address[] memory actorsToUpdate = new address[](1);
        actorsToUpdate[0] = params.validator; //NOTE: currently the same addresses

        _before(actorsToUpdate);

        (bool success, bytes memory returnData) =
            _validateActionablePendingActionsCall(params.previousActionsData, params.maxValidations, params.txValue);

        validateActionablePendingActionsPostconditions(success, returnData, actorsToUpdate, params);
    }

    function fuzz_liquidate() public setCurrentActor {
        LiquidateParams memory params = liquidatePreconditions();
        fuzz_setPrice(0); //here we are just updating oracle timestamp with the same price we already have

        address[] memory actorsToUpdate = new address[](1);
        actorsToUpdate[0] = params.user;

        _before(actorsToUpdate);

        (bool success, bytes memory returnData) = _liquidateCall(createPythData());

        liquidatePostconditions(success, returnData, actorsToUpdate);
    }
}

// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

import "./FuzzAdmin.sol";
import "./helper/postconditions/PostconditionsUsdnProtocolVault.sol";
import "./helper/preconditions/PreconditionsUsdnProtocolVault.sol";

contract FuzzUsdnProtocolVault is PreconditionsUsdnProtocolVault, PostconditionsUsdnProtocolVault, FuzzAdmin {
    function fuzz_initiateDeposit(uint256 ETHAmountSeed, uint128 amountDesiredSeed)
        public
        setCurrentActor
        enforceOneActionPerCall
    {
        InitiateDepositParams memory params = initiateDepositPreconditions(ETHAmountSeed, amountDesiredSeed);
        address[] memory actorsToUpdate = new address[](2);
        actorsToUpdate[0] = params.to;
        actorsToUpdate[1] = params.validator; //NOTE: currently the same addresses

        _before(actorsToUpdate);

        (bool success, bytes memory returnData) = _initiateDepositCall(
            params.wstEthAmount,
            params.amountDesired,
            params.to,
            params.validator,
            params.deadline,
            createPythData(),
            params.previousActionsData,
            params.txValue
        );
        initiateDepositPostconditions(success, returnData, actorsToUpdate, params);
    }

    function fuzz_validateDeposit() public setCurrentActor enforceOneActionPerCall {
        ValidateDepositParams memory params = validateDepositPreconditions();

        fuzz_setPrice(0); //here we are just updating oracle timestamp with the same price we already have

        address[] memory actorsToUpdate = new address[](3);
        actorsToUpdate[0] = params.pendingAction.to;
        actorsToUpdate[1] = params.validator;
        actorsToUpdate[2] = currentActor;

        _before(actorsToUpdate);

        (bool success, bytes memory returnData) =
            _validateDepositCall(params.validator, createPythData(), params.previousActionsData);

        validateDepositPostconditions(success, returnData, actorsToUpdate, params);
    }

    function fuzz_initiateWithdrawal(uint152 usdnSharesSeed) public setCurrentActor enforceOneActionPerCall {
        InitiateWithdrawalParams memory params = initiateWithdrawalPreconditions(usdnSharesSeed);

        address[] memory actorsToUpdate = new address[](1);
        actorsToUpdate[0] = params.validator;

        _before(actorsToUpdate);

        (bool success, bytes memory returnData) = _initiateWithdrawalCall(
            params.usdnShares,
            params.amountDesired,
            params.to,
            params.validator,
            params.deadline,
            createPythData(),
            params.previousActionsData,
            params.txValue
        );

        initiateWithdrawalPostconditions(success, returnData, actorsToUpdate, params);
    }

    function fuzz_validateWithdrawal() public setCurrentActor enforceOneActionPerCall {
        ValidateWithdrawalParams memory params = validateWithdrawalPreconditions();

        fuzz_setPrice(0); //here we are just updating oracle timestamp with the same price we already have

        address[] memory actorsToUpdate = new address[](3);
        actorsToUpdate[0] = params.pendingAction.to;
        actorsToUpdate[1] = params.validator;
        actorsToUpdate[2] = currentActor;

        _before(actorsToUpdate);

        (bool success, bytes memory returnData) =
            _validateWithdrawalCall(params.validator, createPythData(), params.previousActionsData);

        validateWithdrawalPostconditions(success, returnData, actorsToUpdate, params);
    }
}

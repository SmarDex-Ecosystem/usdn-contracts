// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.26;

import "./FuzzAdmin.sol";
import "./helper/postconditions/PostconditionsRebalancer.sol";
import "./helper/preconditions/PreconditionsRebalancer.sol";

contract FuzzRebalancer is PreconditionsRebalancer, PostconditionsRebalancer, FuzzAdmin {
    function fuzz_initiateDepositAssets(uint88 amountSeed) public setCurrentActor {
        InitiateDepositAssetsParams memory params = initiateDepositAssetsPreconditions(amountSeed);

        address[] memory actorsToUpdate = new address[](2);
        actorsToUpdate[0] = params.to;
        actorsToUpdate[1] = currentActor;

        _before(actorsToUpdate);

        (bool success, bytes memory returnData) = _initiateDepositAssetsCall(params.amount, params.to);

        initiateDepositAssetsPostconditions(success, returnData, actorsToUpdate);
    }

    function fuzz_validateDepositAssets() public setCurrentActor {
        address[] memory actorsToUpdate = new address[](1);
        actorsToUpdate[0] = currentActor;

        _before(actorsToUpdate);
        (bool success, bytes memory returnData) = _validateDepositAssetsCall();

        validateDepositAssetsPostconditions(success, returnData, actorsToUpdate);
    }

    function fuzz_resetDepositAssets() public setCurrentActor {
        // ResetDepositAssetsParams memory params = resetDepositAssetsPreconditions();

        address[] memory actorsToUpdate = new address[](1);
        actorsToUpdate[0] = currentActor;

        _before(actorsToUpdate);

        (bool success, bytes memory returnData) = _resetDepositAssetsCall();

        resetDepositAssetsPostconditions(success, returnData, actorsToUpdate);
    }

    function fuzz_initiateWithdrawAssets() public setCurrentActor {
        // InitiateWithdrawAssetsParams memory params = initiateWithdrawAssetsPreconditions();

        address[] memory actorsToUpdate = new address[](1);
        actorsToUpdate[0] = currentActor;

        _before(actorsToUpdate);

        (bool success, bytes memory returnData) = _initiateWithdrawAssetsCall();

        initiateWithdrawAssetsPostconditions(success, returnData, actorsToUpdate);
    }

    function fuzz_validateWithdrawAssets(uint88 amountSeed) public setCurrentActor {
        ValidateWithdrawAssetsParams memory params = validateWithdrawAssetsPreconditions(amountSeed);

        address[] memory actorsToUpdate = new address[](1);
        actorsToUpdate[0] = params.user;

        _before(actorsToUpdate);

        (bool success, bytes memory returnData) = _validateWithdrawAssetsCall(params.amount, params.user);

        validateWithdrawAssetsPostconditions(success, returnData, actorsToUpdate);
    }

    function fuzz_initiateClosePositioninRebalancer(uint88 amountSeed) public payable setCurrentActor {
        InitiateClosePositionParamsInRebalancer memory params =
            initiateClosePositionInRebalancerPreconditions(amountSeed);

        address[] memory actorsToUpdate = new address[](1);
        actorsToUpdate[0] = currentActor; //NOTE: currently current actor == to

        _before(actorsToUpdate);

        (bool success, bytes memory returnData) = _initiateClosePositionCallInRebalancer(
            params.amount,
            params.to, //rebalancer
            params.validator,
            params.userMinPrice,
            params.deadline,
            createPythData(),
            params.previousActionsData,
            params.delegationData,
            params.txValue
        );

        initiateClosePositionPostconditionsInRebalancer(success, returnData, actorsToUpdate);
    }
}

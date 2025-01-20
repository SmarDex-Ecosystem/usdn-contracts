// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

import { FuzzAdmin } from "./FuzzAdmin.sol";
import { PostConditionsRebalancer } from "./helper/postConditions/PostConditionsRebalancer.sol";
import { PreConditionsRebalancer } from "./helper/preConditions/PreConditionsRebalancer.sol";

contract FuzzRebalancer is PreConditionsRebalancer, PostConditionsRebalancer, FuzzAdmin {
    function fuzz_initiateDepositAssets(uint88 amountSeed) public setCurrentActor {
        InitiateDepositAssetsParams memory params = initiateDepositAssetsPreconditions(amountSeed);

        address[] memory actorsToUpdate = new address[](2);
        actorsToUpdate[0] = params.to;
        actorsToUpdate[1] = currentActor;

        _before(actorsToUpdate);

        (bool success, bytes memory returnData) = _initiateDepositAssetsCall(params.amount, params.to);

        initiateDepositAssetsPostConditions(success, returnData, actorsToUpdate, params);
    }

    function fuzz_validateDepositAssets() public setCurrentActor {
        ValidateDepositAssetsParams memory params = validateDepositAssetsPreconditions();

        address[] memory actorsToUpdate = new address[](1);
        actorsToUpdate[0] = currentActor;

        _before(actorsToUpdate);
        (bool success, bytes memory returnData) = _validateDepositAssetsCall();

        validateDepositAssetsPostConditions(success, returnData, actorsToUpdate, params);
    }

    function fuzz_resetDepositAssets() public setCurrentActor {
        ResetDepositAssetsParams memory params = resetDepositAssetsPreconditions();

        address[] memory actorsToUpdate = new address[](1);
        actorsToUpdate[0] = currentActor;

        _before(actorsToUpdate);

        (bool success, bytes memory returnData) = _resetDepositAssetsCall();

        resetDepositAssetsPostConditions(success, returnData, actorsToUpdate, params);
    }

    function fuzz_initiateWithdrawAssets() public setCurrentActor {
        InitiateWithdrawAssetsParams memory params = initiateWithdrawAssetsPreconditions();

        address[] memory actorsToUpdate = new address[](1);
        actorsToUpdate[0] = currentActor;

        _before(actorsToUpdate);

        (bool success, bytes memory returnData) = _initiateWithdrawAssetsCall();

        initiateWithdrawAssetsPostConditions(success, returnData, actorsToUpdate, params);
    }

    function fuzz_validateWithdrawAssets(uint88 amountSeed) public setCurrentActor {
        ValidateWithdrawAssetsParams memory params = validateWithdrawAssetsPreconditions(amountSeed);

        address[] memory actorsToUpdate = new address[](1);
        actorsToUpdate[0] = params.user;

        _before(actorsToUpdate);

        (bool success, bytes memory returnData) = _validateWithdrawAssetsCall(params.amount, params.user);

        validateWithdrawAssetsPostConditions(success, returnData, actorsToUpdate, params);
    }

    function fuzz_initiateClosePositionInRebalancer(uint88 amountSeed) public payable setCurrentActor {
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

        initiateClosePositionPostConditionsInRebalancer(success, returnData, actorsToUpdate, params);
    }
}

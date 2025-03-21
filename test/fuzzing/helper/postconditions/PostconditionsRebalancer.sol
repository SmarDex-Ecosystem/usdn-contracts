// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

import "./PostconditionsBase.sol";

abstract contract PostconditionsRebalancer is PostconditionsBase {
    function initiateDepositAssetsPostconditions(
        bool success,
        bytes memory returnData,
        address[] memory actorsToUpdate,
        InitiateDepositAssetsParams memory params
    ) internal {
        if (success) {
            _after(actorsToUpdate);

            onSuccessInvariantsGeneral(returnData);
        } else {
            onFailInvariantsGeneral(returnData);
        }
    }

    function validateDepositAssetsPostconditions(
        bool success,
        bytes memory returnData,
        address[] memory actorsToUpdate,
        ValidateDepositAssetsParams memory params
    ) internal {
        if (success) {
            _after(actorsToUpdate);

            onSuccessInvariantsGeneral(returnData);
        } else {
            onFailInvariantsGeneral(returnData);
        }
    }

    function resetDepositAssetsPostconditions(
        bool success,
        bytes memory returnData,
        address[] memory actorsToUpdate,
        ResetDepositAssetsParams memory params
    ) internal {
        if (success) {
            _after(actorsToUpdate);

            onSuccessInvariantsGeneral(returnData);
        } else {
            onFailInvariantsGeneral(returnData);
        }
    }

    function initiateWithdrawAssetsPostconditions(
        bool success,
        bytes memory returnData,
        address[] memory actorsToUpdate,
        InitiateWithdrawAssetsParams memory params
    ) internal {
        if (success) {
            _after(actorsToUpdate);

            onSuccessInvariantsGeneral(returnData);
        } else {
            onFailInvariantsGeneral(returnData);
        }
    }

    function validateWithdrawAssetsPostconditions(
        bool success,
        bytes memory returnData,
        address[] memory actorsToUpdate,
        ValidateWithdrawAssetsParams memory params
    ) internal {
        if (success) {
            _after(actorsToUpdate);

            onSuccessInvariantsGeneral(returnData);
        } else {
            onFailInvariantsGeneral(returnData);
        }
    }

    function initiateClosePositionPostconditionsInRebalancer(
        bool success,
        bytes memory returnData,
        address[] memory actorsToUpdate,
        InitiateClosePositionParamsInRebalancer memory params
    ) internal {
        if (success) {
            _after(actorsToUpdate);

            onSuccessInvariantsGeneral(returnData);
        } else {
            onFailInvariantsGeneral(returnData);
        }
    }
}

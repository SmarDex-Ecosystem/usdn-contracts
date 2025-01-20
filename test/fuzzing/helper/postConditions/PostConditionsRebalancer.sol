// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

import { PostConditionsBase } from "./PostConditionsBase.sol";

abstract contract PostConditionsRebalancer is PostConditionsBase {
    function initiateDepositAssetsPostConditions(
        bool success,
        bytes memory returnData,
        address[] memory actorsToUpdate,
        InitiateDepositAssetsParams memory
    ) internal {
        if (success) {
            _after(actorsToUpdate);

            onSuccessInvariantsGeneral(returnData);
        } else {
            onFailInvariantsGeneral(returnData);
        }
    }

    function validateDepositAssetsPostConditions(
        bool success,
        bytes memory returnData,
        address[] memory actorsToUpdate,
        ValidateDepositAssetsParams memory
    ) internal {
        if (success) {
            _after(actorsToUpdate);

            onSuccessInvariantsGeneral(returnData);
        } else {
            onFailInvariantsGeneral(returnData);
        }
    }

    function resetDepositAssetsPostConditions(
        bool success,
        bytes memory returnData,
        address[] memory actorsToUpdate,
        ResetDepositAssetsParams memory
    ) internal {
        if (success) {
            _after(actorsToUpdate);

            onSuccessInvariantsGeneral(returnData);
        } else {
            onFailInvariantsGeneral(returnData);
        }
    }

    function initiateWithdrawAssetsPostConditions(
        bool success,
        bytes memory returnData,
        address[] memory actorsToUpdate,
        InitiateWithdrawAssetsParams memory
    ) internal {
        if (success) {
            _after(actorsToUpdate);

            onSuccessInvariantsGeneral(returnData);
        } else {
            onFailInvariantsGeneral(returnData);
        }
    }

    function validateWithdrawAssetsPostConditions(
        bool success,
        bytes memory returnData,
        address[] memory actorsToUpdate,
        ValidateWithdrawAssetsParams memory
    ) internal {
        if (success) {
            _after(actorsToUpdate);

            onSuccessInvariantsGeneral(returnData);
        } else {
            onFailInvariantsGeneral(returnData);
        }
    }

    function initiateClosePositionPostConditionsInRebalancer(
        bool success,
        bytes memory returnData,
        address[] memory actorsToUpdate,
        InitiateClosePositionParamsInRebalancer memory
    ) internal {
        if (success) {
            _after(actorsToUpdate);

            onSuccessInvariantsGeneral(returnData);
        } else {
            onFailInvariantsGeneral(returnData);
        }
    }
}

// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.26;

import "./PostconditionsBase.sol";

abstract contract PostconditionsRebalancer is PostconditionsBase {
    function initiateDepositAssetsPostconditions(bool success, bytes memory returnData, address[] memory actorsToUpdate)
        internal
    {
        if (success) {
            _after(actorsToUpdate);

            onSuccessInvariantsGeneral();
        } else {
            onFailInvariantsGeneral(returnData);
        }
    }

    function validateDepositAssetsPostconditions(bool success, bytes memory returnData, address[] memory actorsToUpdate)
        internal
    {
        if (success) {
            _after(actorsToUpdate);

            onSuccessInvariantsGeneral();
        } else {
            onFailInvariantsGeneral(returnData);
        }
    }

    function resetDepositAssetsPostconditions(bool success, bytes memory returnData, address[] memory actorsToUpdate)
        internal
    {
        if (success) {
            _after(actorsToUpdate);

            onSuccessInvariantsGeneral();
        } else {
            onFailInvariantsGeneral(returnData);
        }
    }

    function initiateWithdrawAssetsPostconditions(
        bool success,
        bytes memory returnData,
        address[] memory actorsToUpdate
    ) internal {
        if (success) {
            _after(actorsToUpdate);

            onSuccessInvariantsGeneral();
        } else {
            onFailInvariantsGeneral(returnData);
        }
    }

    function validateWithdrawAssetsPostconditions(
        bool success,
        bytes memory returnData,
        address[] memory actorsToUpdate
    ) internal {
        if (success) {
            _after(actorsToUpdate);

            onSuccessInvariantsGeneral();
        } else {
            onFailInvariantsGeneral(returnData);
        }
    }

    function initiateClosePositionPostconditionsInRebalancer(
        bool success,
        bytes memory returnData,
        address[] memory actorsToUpdate
    ) internal {
        if (success) {
            _after(actorsToUpdate);

            onSuccessInvariantsGeneral();
        } else {
            onFailInvariantsGeneral(returnData);
        }
    }
}

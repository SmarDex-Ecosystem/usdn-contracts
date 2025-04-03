// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.26;

import { PostconditionsBase } from "./PostconditionsBase.sol";

abstract contract PostconditionsUsdnProtocolVault is PostconditionsBase {
    function initiateDepositPostconditions(
        bool success,
        bytes memory returnData,
        address[] memory actorsToUpdate,
        InitiateDepositParams memory params
    ) internal {
        if (success) {
            _after(actorsToUpdate);
            bool initiatedDeposit = abi.decode(returnData, (bool));
            if (initiatedDeposit) {
                invariant_DEPI_01(actorsToUpdate[0], initiatedDeposit);
                invariant_DEPI_02(actorsToUpdate[0], params);
                invariant_DEPI_03(actorsToUpdate[0]);
                invariant_DEPI_04(params, initiatedDeposit);
                invariant_DEPI_05(params); //failed
            }
            onSuccessInvariantsGeneral();
        } else {
            onFailInvariantsGeneral(returnData);
        }
    }

    function validateDepositPostconditions(
        bool success,
        bytes memory returnData,
        address[] memory actorsToUpdate,
        ValidateDepositParams memory params
    ) internal {
        if (success) {
            _after(actorsToUpdate);

            //funciton internal bool return
            if (abi.decode(returnData, (bool))) {
                invariant_DEPV_01(actorsToUpdate[0]); //increasing number of shares
                invariant_DEPV_02(actorsToUpdate[0], actorsToUpdate[2]);
                invariant_DEPV_03(actorsToUpdate[0], actorsToUpdate[1]);
            }

            invariant_DEPV_04(actorsToUpdate[0], actorsToUpdate[1]);
            invariant_DEPV_05(params); //Failed, acknowledged edge case
            invariant_DEPV_06(actorsToUpdate[2]);
            invariant_DEPV_07(params);
            invariant_DEPV_08(actorsToUpdate[1]);
            invariant_DEPV_09(actorsToUpdate[0]);

            onSuccessInvariantsGeneral();
        } else {
            onFailInvariantsGeneral(returnData);
        }
    }

    function initiateWithdrawalPostconditions(
        bool success,
        bytes memory returnData,
        address[] memory actorsToUpdate,
        InitiateWithdrawalParams memory params
    ) internal {
        if (success) {
            _after(actorsToUpdate);
            bool initiatedWithdrawal = abi.decode(returnData, (bool));
            if (initiatedWithdrawal) {
                invariant_WITHI_01(actorsToUpdate[0], initiatedWithdrawal);
                invariant_WITHI_02(actorsToUpdate[0], params);
                invariant_WITHI_03(params, initiatedWithdrawal);
                invariant_WITHI_04(params);
            }

            onSuccessInvariantsGeneral();
        } else {
            onFailInvariantsGeneral(returnData);
        }
    }

    function validateWithdrawalPostconditions(
        bool success,
        bytes memory returnData,
        address[] memory actorsToUpdate,
        ValidateWithdrawalParams memory params
    ) internal {
        if (success) {
            _after(actorsToUpdate);
            invariant_WITHV_01(actorsToUpdate[0]);
            if (abi.decode(returnData, (bool))) {
                invariant_WITHV_02(actorsToUpdate[0]);
                invariant_WITHV_03();
                invariant_WITHV_04(params);
                invariant_WITHV_05();
            }
            onSuccessInvariantsGeneral();
        } else {
            onFailInvariantsGeneral(returnData);
        }
    }
}

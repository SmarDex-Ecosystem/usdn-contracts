// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.26;

import { PostconditionsBase } from "./PostconditionsBase.sol";

import { IUsdnProtocolTypes as Types } from "../../../../src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";

abstract contract PostconditionsUsdnProtocolActions is PostconditionsBase {
    function initiateOpenPositionPostconditions(
        bool success,
        bytes memory returnData,
        address[] memory actorsToUpdate,
        InitiateOpenPositionParams memory params,
        address currentActor
    ) internal {
        if (success) {
            _after(actorsToUpdate);

            (bool opened,) = abi.decode(returnData, (bool, Types.PositionId));
            addPositionToArray(opened, returnData);

            if (opened) {
                invariant_POSOPNI_01(params, opened);
                invariant_POSOPNI_02(actorsToUpdate[0], params, opened);
                invariant_POSOPNI_03(params);
                invariant_POSOPNI_04(currentActor, params);
            }
            onSuccessInvariantsGeneral();
        } else {
            onFailInvariantsGeneral(returnData);
        }
    }

    function validateOpenPositionPostconditions(
        bool success,
        bytes memory returnData,
        address[] memory actorsToUpdate,
        ValidateOpenPositionParams memory params
    ) internal {
        if (success) {
            _after(actorsToUpdate);
            (Types.LongActionOutcome outcome,) = abi.decode(returnData, (Types.LongActionOutcome, Types.PositionId));

            invariant_POSOPNV_01(actorsToUpdate[0], actorsToUpdate[1], params, outcome);
            invariant_POSOPNV_02(params, outcome);

            invariant_POSOPNV_03(params, outcome);
            invariant_POSOPNV_04(actorsToUpdate[1], outcome);

            onSuccessInvariantsGeneral();
        } else {
            onFailInvariantsGeneral(returnData);
        }
    }

    function initiateClosePositionPostconditions(
        bool success,
        bytes memory returnData,
        address[] memory actorsToUpdate,
        InitiateClosePositionParams memory params
    ) internal {
        if (success) {
            _after(actorsToUpdate);

            Types.LongActionOutcome outcome = abi.decode(returnData, (Types.LongActionOutcome));
            if (outcome == Types.LongActionOutcome.Processed) {
                removePositionFromArray(true, params);
            }
            invariant_POSCLOSI_01(actorsToUpdate[0], outcome);
            invariant_POSCLOSI_02(actorsToUpdate[0], outcome);
            invariant_POSCLOSI_03(outcome);

            invariant_POSCLOSI_04(actorsToUpdate[0], outcome);
            invariant_POSCLOSI_05();

            onSuccessInvariantsGeneral();
        } else {
            onFailInvariantsGeneral(returnData);
        }
    }

    function validateClosePositionPostconditions(
        bool success,
        bytes memory returnData,
        address[] memory actorsToUpdate,
        ValidateClosePositionParams memory params
    ) internal {
        if (success) {
            _after(actorsToUpdate);

            Types.LongActionOutcome outcome = abi.decode(returnData, (Types.LongActionOutcome));
            invariant_POSCLOSV_01(actorsToUpdate[1], outcome);
            invariant_POSCLOSV_02(outcome);
            invariant_POSCLOSV_03(params, outcome);
            invariant_POSCLOSV_04(params, outcome);
            invariant_POSCLOSV_05(actorsToUpdate[0], params, outcome);
            invariant_POSCLOSV_06(actorsToUpdate[0], params, outcome);
            invariant_POSCLOSV_07(actorsToUpdate[1], actorsToUpdate[2], outcome);
            invariant_POSCLOSV_08(actorsToUpdate[0], actorsToUpdate[2], outcome);
            invariant_POSCLOSV_09(actorsToUpdate[0], actorsToUpdate[1], outcome);
            invariant_POSCLOSV_10(actorsToUpdate[0], actorsToUpdate[1], outcome);

            onSuccessInvariantsGeneral();
        } else {
            onFailInvariantsGeneral(returnData);
        }
    }

    function validateActionablePendingActionsPostconditions(
        bool success,
        bytes memory returnData,
        address[] memory actorsToUpdate,
        ValidateActionablePendingActionsParams memory params
    ) internal {
        if (success) {
            _after(actorsToUpdate);

            uint256 validatedActions = abi.decode(returnData, (uint256));
            invariant_PENDACTV_01(validatedActions, params);
            invariant_PENDACTV_02(actorsToUpdate[0], params);
            invariant_PENDACTV_03(params);

            onSuccessInvariantsGeneral();
        } else {
            onFailInvariantsGeneral(returnData);
        }
    }

    function liquidatePostconditions(bool success, bytes memory returnData, address[] memory actorsToUpdate) internal {
        if (success) {
            _after(actorsToUpdate);

            // @todo not used liquidatedTicks?
            // Types.LiqTickInfo[] memory liquidatedTicks_ = abi.decode(returnData, (Types.LiqTickInfo[]));
            onSuccessInvariantsGeneral();
        } else {
            onFailInvariantsGeneral(returnData);
        }
    }
}

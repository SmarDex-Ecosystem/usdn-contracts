// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.26;

import { IUsdnProtocolTypes } from "../../../../src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import { Properties } from "../../properties/Properties.sol";

abstract contract PostconditionsBase is Properties {
    function onSuccessInvariantsGeneral() internal {
        invariant_GLOB_01();
        invariant_GLOB_02();
        invariant_GLOB_03();
        invariant_GLOB_04();
        invariant_GLOB_05();
        invariant_GLOB_06();
        invariant_GLOB_07();
    }

    // Admin functions don't need to check funding (invariant_GLOB_03)
    function onSuccessInvariantsAdmin() internal {
        invariant_GLOB_01();
        invariant_GLOB_02();
        invariant_GLOB_04();
        invariant_GLOB_05();
        invariant_GLOB_06();
        invariant_GLOB_07();
    }

    function onFailInvariantsGeneral(bytes memory returnData) internal {
        invariant_ERR(returnData);
    }

    function addPositionToArray(bool success, bytes memory returnData) internal {
        if (success) {
            (bool decodedSuccess, IUsdnProtocolTypes.PositionId memory posId) =
                abi.decode(returnData, (bool, IUsdnProtocolTypes.PositionId));
            if (decodedSuccess) {
                positionIds.push(posId);
            }
        }
    }

    function removePositionFromArray(bool success, InitiateClosePositionParams memory params) internal {
        if (success) {
            for (uint256 i = 0; i < positionIds.length; i++) {
                if (_comparePositionIds(positionIds[i], params.positionId)) {
                    positionIds[i] = positionIds[positionIds.length - 1];
                    positionIds.pop();
                    break;
                }
            }
        }
    }

    function _comparePositionIds(IUsdnProtocolTypes.PositionId memory a, IUsdnProtocolTypes.PositionId memory b)
        internal
        pure
        returns (bool)
    {
        return a.tick == b.tick && a.tickVersion == b.tickVersion && a.index == b.index;
    }
}

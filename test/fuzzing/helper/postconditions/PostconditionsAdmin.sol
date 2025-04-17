// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.26;

import { PostconditionsBase } from "./PostconditionsBase.sol";

abstract contract PostconditionsAdmin is PostconditionsBase {
    /* -------------------------------------------------------------------------- */
    /*                                USDN Protocol                               */
    /* -------------------------------------------------------------------------- */
    function setAdminPostconditions(bool success, bytes memory returnData) internal {
        Invariant_ADMIN_01(success);
        if (success) {
            onSuccessInvariantsAdmin();
        } else {
            onFailInvariantsGeneral(returnData);
        }
    }
}

// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.26;

import { PostconditionsBase } from "./PostconditionsBase.sol";

// @todo add more admin invariants
abstract contract PostconditionsAdmin is PostconditionsBase {
    /* -------------------------------------------------------------------------- */
    /*                                USDN Protocol                               */
    /* -------------------------------------------------------------------------- */
    function setValidatorDeadlinesPostconditions(bool success, bytes memory returnData) internal {
        if (success) {
            Invariant_ADMIN_01(success);
        } else {
            onFailInvariantsGeneral(returnData);
        }
    }

    function setMinLeveragePostconditions(bool success, bytes memory returnData) internal {
        if (success) {
            Invariant_ADMIN_01(success);
        } else {
            onFailInvariantsGeneral(returnData);
        }
    }

    function setMaxLeveragePostconditions(bool success, bytes memory returnData) internal {
        if (success) {
            Invariant_ADMIN_01(success);
        } else {
            onFailInvariantsGeneral(returnData);
        }
    }

    function setLiquidationPenaltyPostconditions(bool success, bytes memory returnData) internal {
        if (success) {
            Invariant_ADMIN_01(success);
        } else {
            onFailInvariantsGeneral(returnData);
        }
    }

    function setEMAPeriodPostconditions(bool success, bytes memory returnData) internal {
        if (success) {
            Invariant_ADMIN_01(success);
        } else {
            onFailInvariantsGeneral(returnData);
        }
    }

    function setFundingSFPostconditions(bool success, bytes memory returnData) internal {
        if (success) {
            Invariant_ADMIN_01(success);
        } else {
            onFailInvariantsGeneral(returnData);
        }
    }

    function setProtocolFeeBpsPostconditions(bool success, bytes memory returnData) internal {
        if (success) {
            Invariant_ADMIN_01(success);
        } else {
            onFailInvariantsGeneral(returnData);
        }
    }

    function setPositionFeeBpsPostconditions(bool success, bytes memory returnData) internal {
        if (success) {
            Invariant_ADMIN_01(success);
        } else {
            onFailInvariantsGeneral(returnData);
        }
    }

    function setVaultFeeBpsPostconditions(bool success, bytes memory returnData) internal {
        if (success) {
            Invariant_ADMIN_01(success);
        } else {
            onFailInvariantsGeneral(returnData);
        }
    }

    function setSdexRewardsRatioBpsPostconditions(bool success, bytes memory returnData) internal {
        if (success) {
            Invariant_ADMIN_01(success);
        } else {
            onFailInvariantsGeneral(returnData);
        }
    }

    function setRebalancerBonusBpsPostconditions(bool success, bytes memory returnData) internal {
        if (success) {
            Invariant_ADMIN_01(success);
        } else {
            onFailInvariantsGeneral(returnData);
        }
    }

    function setSdexBurnOnDepositRatioPostconditions(bool success, bytes memory returnData) internal {
        if (success) {
            Invariant_ADMIN_01(success);
        } else {
            onFailInvariantsGeneral(returnData);
        }
    }

    function setSecurityDepositValuePostconditions(bool success, bytes memory returnData) internal {
        if (success) {
            Invariant_ADMIN_01(success);
        } else {
            onFailInvariantsGeneral(returnData);
        }
    }

    function setExpoImbalanceLimitsPostconditions(bool success, bytes memory returnData) internal {
        if (success) {
            Invariant_ADMIN_01(success);
        } else {
            onFailInvariantsGeneral(returnData);
        }
    }

    function setMinLongPositionPostconditions(bool success, bytes memory returnData) internal {
        if (success) {
            Invariant_ADMIN_01(success);
        } else {
            onFailInvariantsGeneral(returnData);
        }
    }

    function setSafetyMarginBpsPostconditions(bool success, bytes memory returnData) internal {
        if (success) {
            Invariant_ADMIN_01(success);
        } else {
            onFailInvariantsGeneral(returnData);
        }
    }

    function setLiquidationIterationPostconditions(bool success, bytes memory returnData) internal {
        if (success) {
            Invariant_ADMIN_01(success);
        } else {
            onFailInvariantsGeneral(returnData);
        }
    }

    function setFeeThresholdPostconditions(bool success, bytes memory returnData) internal {
        if (success) {
            Invariant_ADMIN_01(success);
        } else {
            onFailInvariantsGeneral(returnData);
        }
    }

    function setTargetUsdnPricePostconditions(bool success, bytes memory returnData) internal {
        if (success) {
            Invariant_ADMIN_01(success);
        } else {
            onFailInvariantsGeneral(returnData);
        }
    }

    function setUsdnRebaseThresholdPostconditions(bool success, bytes memory returnData) internal {
        if (success) {
            Invariant_ADMIN_01(success);
        } else {
            onFailInvariantsGeneral(returnData);
        }
    }

    /* -------------------------------------------------------------------------- */
    /*                                 Rebalancer                                 */
    /* -------------------------------------------------------------------------- */

    function setPositionMaxLeveragePostconditions(bool success, bytes memory returnData) internal {
        if (success) {
            Invariant_ADMIN_01(success);
        } else {
            onFailInvariantsGeneral(returnData);
        }
    }

    function setMinAssetDepositPostconditions(bool success, bytes memory returnData) internal {
        if (success) {
            Invariant_ADMIN_01(success);
        } else {
            onFailInvariantsGeneral(returnData);
        }
    }

    function setTimeLimitsPostconditions(bool success, bytes memory returnData) internal {
        if (success) {
            Invariant_ADMIN_01(success);
        } else {
            onFailInvariantsGeneral(returnData);
        }
    }

    /* -------------------------------------------------------------------------- */
    /*                             Liquidation Manger                             */
    /* -------------------------------------------------------------------------- */
}

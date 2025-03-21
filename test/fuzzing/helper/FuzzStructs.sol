// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

import "../FuzzSetup.sol";
import "../util/FunctionCalls.sol";
import "@perimetersec/fuzzlib/src/FuzzBase.sol";

/* solhint-disable numcast/safe-cast */
abstract contract FuzzStructs is FuzzSetup {
    struct InitiateDepositParams {
        address to;
        address payable validator;
        uint128 wstEthAmount;
        uint256 amountDesired;
        uint256 deadline;
        IUsdnProtocolTypes.PreviousActionsData previousActionsData;
        IUsdnProtocolTypes.PendingAction lastAction;
        uint256 wstethPendingActions;
        uint256 txValue;
    }

    struct ValidateDepositParams {
        address payable validator;
        IUsdnProtocolTypes.DepositPendingAction pendingAction;
        IUsdnProtocolTypes.PreviousActionsData previousActionsData;
        IUsdnProtocolTypes.PendingAction lastAction;
        int256 usdnPendingActions;
        uint256 wstethPendingActions;
    }

    struct InitiateWithdrawalParams {
        address to;
        address payable validator;
        uint128 usdnShares;
        uint256 amountDesired;
        uint256 deadline;
        IUsdnProtocolTypes.PreviousActionsData previousActionsData;
        IUsdnProtocolTypes.PendingAction lastAction;
        int256 usdnPendingActions;
        uint256 txValue;
    }

    struct ValidateWithdrawalParams {
        address payable validator;
        IUsdnProtocolTypes.PendingAction pendingAction;
        IUsdnProtocolTypes.PreviousActionsData previousActionsData;
        IUsdnProtocolTypes.PendingAction lastAction;
        int256 usdnPendingActions;
        uint256 wstethPendingActions;
    }

    struct InitiateOpenPositionParams {
        uint128 amount;
        uint128 desiredLiqPrice;
        uint128 userMaxPrice;
        uint256 userMaxLeverage;
        address to;
        address payable validator;
        uint256 deadline;
        IUsdnProtocolTypes.PendingAction pendingAction;
        IUsdnProtocolTypes.PreviousActionsData previousActionsData;
        IUsdnProtocolTypes.PendingAction lastAction;
        uint256 wstethPendingActions;
        uint256 txValue;
    }

    struct ValidateOpenPositionParams {
        address payable validator;
        int256 currentPrice;
        IUsdnProtocolTypes.PendingAction pendingAction;
        IUsdnProtocolTypes.PreviousActionsData previousActionsData;
        IUsdnProtocolTypes.PendingAction lastAction;
        uint256 wstethPendingActions;
        uint256 txValue;
    }

    struct InitiateClosePositionParams {
        IUsdnProtocolTypes.PositionId positionId;
        uint128 amountToClose;
        address to;
        address payable validator;
        uint256 txValue;
    }

    struct ValidateClosePositionParams {
        address user;
        address payable validator;
        int256 currentPrice;
        IUsdnProtocolTypes.PreviousActionsData previousActionsData;
        IUsdnProtocolTypes.PendingAction lastAction;
        uint256 wstethPendingActions;
        uint256 txValue;
        uint256 closeAmount;
    }

    struct ValidateActionablePendingActionsParams {
        address payable validator;
        IUsdnProtocolTypes.PreviousActionsData previousActionsData;
        uint256 maxValidations;
        uint256 securityDeposit;
        uint256 actionsLength;
        uint256 txValue;
    }

    struct InitiateDepositAssetsParams {
        uint88 amount;
        address to;
    }

    struct ValidateDepositAssetsParams {
        address user;
    }

    struct ResetDepositAssetsParams {
        address user;
    }

    struct InitiateWithdrawAssetsParams {
        address user;
    }

    struct ValidateWithdrawAssetsParams {
        address user;
        uint88 amount;
    }

    struct InitiateClosePositionParamsInRebalancer {
        address user;
        address to;
        address payable validator;
        uint88 amount;
        uint256 userMinPrice;
        uint256 deadline;
        uint256 txValue;
        IUsdnProtocolTypes.PreviousActionsData previousActionsData;
        IUsdnProtocolTypes.PendingAction lastAction;
        bytes delegationData;
    }

    struct LiquidateParams {
        address user;
    }
}

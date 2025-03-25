// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

import "./PreconditionsBase.sol";

/* solhint-disable numcast/safe-cast */

abstract contract PreconditionsUsdnProtocolVault is PreconditionsBase {
    function initiateDepositPreconditions(uint256 ETHAmountSeed, uint128 amountDesiredSeed)
        internal
        returns (InitiateDepositParams memory)
    {
        waitDelay();
        InitiateDepositParams memory params;

        // Check pending actions first
        IUsdnProtocolTypes.PendingAction memory action = usdnProtocol.getUserPendingAction(currentActor);

        if (
            action.action != IUsdnProtocolTypes.ProtocolAction.InitiateDeposit
                && action.action != IUsdnProtocolTypes.ProtocolAction.None
        ) {
            revert();
        }

        params.to = currentActor;
        params.validator = payable(currentActor);

        params.wstEthAmount = uint128(fl.clamp(ETHAmountSeed, 10_000, wstETH.balanceOf(params.to)));
        params.amountDesired =
            fl.clamp(ETHAmountSeed, 0, wstETH.balanceOf(params.to) + (wstETH.balanceOf(params.to) / 5));
        params.deadline = type(uint256).max;

        (params.previousActionsData,, params.lastAction,) = getPreviousActionsData(currentActor, createProtocolPrice());

        (, params.wstethPendingActions) = getTokenFromPendingAction(params.lastAction, createProtocolPrice());
        params.txValue = totalValue();

        return params;
    }

    function validateDepositPreconditions() internal returns (ValidateDepositParams memory) {
        waitForValidationDeadline();

        ValidateDepositParams memory params;

        params.validator = payable(currentActor);

        IUsdnProtocolTypes.PendingAction memory action = usdnProtocol.getUserPendingAction(params.validator);

        if (
            action.action != IUsdnProtocolTypes.ProtocolAction.ValidateDeposit
                && action.action != IUsdnProtocolTypes.ProtocolAction.None
        ) {
            revert();
        }

        params.pendingAction = usdnProtocol.i_toDepositPendingAction(action);

        (params.previousActionsData,, params.lastAction,) = getPreviousActionsData(currentActor, createProtocolPrice());

        (params.usdnPendingActions, params.wstethPendingActions) =
            getTokenFromPendingAction(params.lastAction, createProtocolPrice());

        return params;
    }

    function initiateWithdrawalPreconditions(uint152 usdnSharesSeed)
        internal
        returns (InitiateWithdrawalParams memory)
    {
        waitDelay();

        InitiateWithdrawalParams memory params;

        // Check pending actions first
        IUsdnProtocolTypes.PendingAction memory action = usdnProtocol.getUserPendingAction(currentActor);

        if (
            action.action != IUsdnProtocolTypes.ProtocolAction.InitiateWithdrawal
                && action.action != IUsdnProtocolTypes.ProtocolAction.None
        ) {
            revert();
        }

        params.to = currentActor;
        params.validator = payable(currentActor);

        require(usdn.sharesOf(params.to) >= 10_000, "Withdrawal amount is below min amount");
        params.usdnShares = uint128(fl.clamp(usdnSharesSeed, 10_000, usdn.sharesOf(params.to)));
        params.deadline = type(uint256).max;
        params.amountDesired = 1;

        (params.previousActionsData,, params.lastAction,) = getPreviousActionsData(currentActor, createProtocolPrice());

        (params.usdnPendingActions,) = getTokenFromPendingAction(params.lastAction, createProtocolPrice());

        params.txValue = totalValue();

        return params;
    }

    function initiateWithdrawalPreconditionsMultiCall(uint152 usdnSharesSeed)
        internal
        returns (InitiateWithdrawalParams memory)
    {
        waitDelay();

        InitiateWithdrawalParams memory params;

        // Check pending actions first
        // IUsdnProtocolTypes.PendingAction memory action = usdnProtocol.getUserPendingAction(currentActor);

        params.to = currentActor;
        params.validator = payable(currentActor);

        require(usdn.sharesOf(params.to) >= 10_000, "Withdrawal amount is below min amount");
        params.usdnShares = uint128(fl.clamp(usdnSharesSeed, 10_000, usdn.sharesOf(params.to)));
        params.deadline = type(uint256).max;
        params.amountDesired = 1;

        (params.previousActionsData,, params.lastAction,) = getPreviousActionsData(currentActor, createProtocolPrice());

        (params.usdnPendingActions,) = getTokenFromPendingAction(params.lastAction, createProtocolPrice());

        params.txValue = totalValue();

        return params;
    }

    function validateWithdrawalPreconditions() internal returns (ValidateWithdrawalParams memory) {
        waitForValidationDeadline();

        ValidateWithdrawalParams memory params;

        params.validator = payable(currentActor);

        IUsdnProtocolTypes.PendingAction memory action = usdnProtocol.getUserPendingAction(params.validator);

        if (action.action != IUsdnProtocolTypes.ProtocolAction.ValidateWithdrawal) {
            revert();
        }

        params.pendingAction = action;

        (params.previousActionsData,, params.lastAction,) = getPreviousActionsData(currentActor, createProtocolPrice());

        (params.usdnPendingActions, params.wstethPendingActions) =
            getTokenFromPendingAction(params.lastAction, createProtocolPrice());
        return params;
    }

    function validateWithdrawalPreconditionsMultiCall() internal returns (ValidateWithdrawalParams memory) {
        waitForValidationDeadline();

        ValidateWithdrawalParams memory params;

        params.validator = payable(currentActor);

        IUsdnProtocolTypes.PendingAction memory action = usdnProtocol.getUserPendingAction(params.validator);

        params.pendingAction = action;

        (params.previousActionsData,, params.lastAction,) = getPreviousActionsData(currentActor, createProtocolPrice());

        (params.usdnPendingActions, params.wstethPendingActions) =
            getTokenFromPendingAction(params.lastAction, createProtocolPrice());
        return params;
    }
}

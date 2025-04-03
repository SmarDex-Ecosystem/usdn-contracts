// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.26;

import "./PreconditionsBase.sol";

/* solhint-disable numcast/safe-cast */

abstract contract PreconditionsUsdnProtocolActions is PreconditionsBase {
    function initiateOpenPositionPrecondtions(uint256 amountSeed, uint256 leverageSeed)
        internal
        returns (InitiateOpenPositionParams memory params)
    {
        // Check pending actions first
        IUsdnProtocolTypes.PendingAction memory action = usdnProtocol.getUserPendingAction(currentActor);

        if (
            action.action != IUsdnProtocolTypes.ProtocolAction.InitiateOpenPosition
                && action.action != IUsdnProtocolTypes.ProtocolAction.None
        ) {
            revert();
        }

        params.amount = uint128(fl.clamp(amountSeed, usdnProtocol.getMinLongPosition(), wstETH.balanceOf(currentActor)));
        params.userMaxLeverage = usdnProtocol.getMaxLeverage();

        uint256 leverage = fl.clamp(leverageSeed, usdnProtocol.getMinLeverage(), params.userMaxLeverage);

        params.desiredLiqPrice = getLiquidationPrice(uint128(createProtocolPrice()), leverage);
        params.userMaxPrice = type(uint128).max;
        params.to = currentActor;
        params.validator = payable(currentActor);
        params.txValue = totalValue();

        params.pendingAction = usdnProtocol.getUserPendingAction(params.validator);
        (params.previousActionsData,, params.lastAction,) = getPreviousActionsData(currentActor, createProtocolPrice());

        (, params.wstethPendingActions) = getTokenFromPendingAction(params.lastAction, createProtocolPrice());

        logInitiateOpenPositionParams(params, createProtocolPrice(), leverage);

        return params;
    }

    function validateOpenPositionPreconditions() internal returns (ValidateOpenPositionParams memory params) {
        waitForValidationDeadline();

        params.validator = payable(currentActor);

        // Check pending actions
        IUsdnProtocolTypes.PendingAction memory action = usdnProtocol.getUserPendingAction(params.validator);

        if (
            action.action != IUsdnProtocolTypes.ProtocolAction.ValidateOpenPosition
                && action.action != IUsdnProtocolTypes.ProtocolAction.None
        ) {
            revert();
        }

        params.pendingAction = action;
        (params.previousActionsData,, params.lastAction,) = getPreviousActionsData(currentActor, createProtocolPrice());
        (, params.wstethPendingActions) = getTokenFromPendingAction(params.lastAction, createProtocolPrice());

        params.txValue = pythPrice;
        return params;
    }

    function InitiateClosePositionPreconditions(uint256 amountSeed, bool closeFull)
        internal
        returns (InitiateClosePositionParams memory params)
    {
        // Check pending actions first
        IUsdnProtocolTypes.PendingAction memory action = usdnProtocol.getUserPendingAction(currentActor);

        if (
            action.action != IUsdnProtocolTypes.ProtocolAction.InitiateClosePosition
                && action.action != IUsdnProtocolTypes.ProtocolAction.None
        ) {
            revert();
        }

        // avoid empty checks
        if (positionIds.length == 0) {
            return params;
        }

        uint256 positionIdsIndex;
        if (positionIds.length > 0) {
            positionIdsIndex = fl.clamp(amountSeed, 0, positionIds.length - 1);
            params.positionId = positionIds[positionIdsIndex];
        }
        (IUsdnProtocolTypes.Position memory position,) = usdnProtocol.getLongPosition(params.positionId);

        uint256 minLongPosition = usdnProtocol.getMinLongPosition();

        uint256 maxCloseAmount = position.amount > minLongPosition ? position.amount - minLongPosition : 0;

        params.amountToClose = closeFull ? position.amount : uint128(fl.clamp(amountSeed, 10_000, maxCloseAmount));

        params.to = (usdnProtocol.getPositionOwner(params.positionId));
        params.validator = payable(currentActor);
        params.txValue = totalValue();

        currentActor = params.to; //NOTE: Hardcoded call from a position owner
    }

    function validateClosePositionPreconditions() internal returns (ValidateClosePositionParams memory params) {
        waitForValidationDeadline();

        params.validator = payable(currentActor);

        // Check pending actions
        IUsdnProtocolTypes.PendingAction memory action = usdnProtocol.getUserPendingAction(params.validator);

        if (
            action.action != IUsdnProtocolTypes.ProtocolAction.ValidateClosePosition
                && action.action != IUsdnProtocolTypes.ProtocolAction.None
        ) {
            revert();
        }

        IUsdnProtocolTypes.LongPendingAction memory longAction = usdnProtocol.i_toLongPendingAction(action);
        params.closeAmount = longAction.closeAmount;
        params.user = longAction.to;

        (params.previousActionsData,, params.lastAction,) = getPreviousActionsData(currentActor, createProtocolPrice());
        (, params.wstethPendingActions) = getTokenFromPendingAction(params.lastAction, createProtocolPrice());

        params.txValue = pythPrice;
        return params;
    }

    function validateActionablePendingActionsPreconditions(uint256 maxValidations)
        internal
        returns (ValidateActionablePendingActionsParams memory params)
    {
        waitForValidationDeadline();

        params.validator = payable(currentActor);
        params.maxValidations = maxValidations;
        params.txValue = pythPrice;
        (params.previousActionsData, params.securityDeposit,, params.actionsLength) =
            getPreviousActionsData(currentActor, createProtocolPrice());
    }

    function liquidatePreconditions() internal returns (LiquidateParams memory params) {
        waitForValidationDeadline();

        params.user = payable(currentActor);
    }
}

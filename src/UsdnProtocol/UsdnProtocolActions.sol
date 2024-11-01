// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import { IUsdnProtocolActions } from "../interfaces/UsdnProtocol/IUsdnProtocolActions.sol";
import { UsdnProtocolStorage } from "./UsdnProtocolStorage.sol";
import { UsdnProtocolActionsLongLibrary as ActionsLong } from "./libraries/UsdnProtocolActionsLongLibrary.sol";
import { UsdnProtocolActionsUtilsLibrary as ActionsUtils } from "./libraries/UsdnProtocolActionsUtilsLibrary.sol";
import { UsdnProtocolUtilsLibrary as Utils } from "./libraries/UsdnProtocolUtilsLibrary.sol";

abstract contract UsdnProtocolActions is UsdnProtocolStorage, IUsdnProtocolActions {
    /// @inheritdoc IUsdnProtocolActions
    function initiateOpenPosition(
        uint128 amount,
        uint128 desiredLiqPrice,
        uint128 userMaxPrice,
        uint256 userMaxLeverage,
        address to,
        address payable validator,
        uint256 deadline,
        bytes calldata currentPriceData,
        PreviousActionsData calldata previousActionsData
    ) external payable whenNotPaused initializedAndNonReentrant returns (bool success_, PositionId memory posId_) {
        InitiateOpenPositionParams memory params = InitiateOpenPositionParams({
            user: msg.sender,
            to: to,
            validator: validator,
            amount: amount,
            desiredLiqPrice: desiredLiqPrice,
            userMaxPrice: userMaxPrice,
            userMaxLeverage: userMaxLeverage,
            deadline: deadline,
            securityDepositValue: s._securityDepositValue
        });

        return ActionsLong.initiateOpenPosition(s, params, currentPriceData, previousActionsData);
    }

    /// @inheritdoc IUsdnProtocolActions
    function validateOpenPosition(
        address payable validator,
        bytes calldata openPriceData,
        PreviousActionsData calldata previousActionsData
    ) external payable whenNotPaused initializedAndNonReentrant returns (bool success_) {
        return ActionsLong.validateOpenPosition(s, validator, openPriceData, previousActionsData);
    }

    /// @inheritdoc IUsdnProtocolActions
    function initiateClosePosition(
        PositionId calldata posId,
        uint128 amountToClose,
        uint256 userMinPrice,
        address to,
        address payable validator,
        uint256 deadline,
        bytes calldata currentPriceData,
        PreviousActionsData calldata previousActionsData,
        bytes calldata delegationSignature
    ) external payable whenNotPaused initializedAndNonReentrant returns (bool success_) {
        InitiateClosePositionParams memory params = InitiateClosePositionParams({
            to: to,
            validator: validator,
            posId: posId,
            amountToClose: amountToClose,
            userMinPrice: userMinPrice,
            deadline: deadline,
            securityDepositValue: s._securityDepositValue,
            domainSeparatorV4: _domainSeparatorV4()
        });

        return ActionsLong.initiateClosePosition(s, params, currentPriceData, previousActionsData, delegationSignature);
    }

    /// @inheritdoc IUsdnProtocolActions
    function validateClosePosition(
        address payable validator,
        bytes calldata closePriceData,
        PreviousActionsData calldata previousActionsData
    ) external payable whenNotPaused initializedAndNonReentrant returns (bool success_) {
        return ActionsLong.validateClosePosition(s, validator, closePriceData, previousActionsData);
    }

    /// @inheritdoc IUsdnProtocolActions
    function liquidate(bytes calldata currentPriceData)
        external
        payable
        whenNotPaused
        initializedAndNonReentrant
        returns (LiqTickInfo[] memory liquidatedTicks_)
    {
        return ActionsUtils.liquidate(s, currentPriceData);
    }

    /// @inheritdoc IUsdnProtocolActions
    function validateActionablePendingActions(PreviousActionsData calldata previousActionsData, uint256 maxValidations)
        external
        payable
        whenNotPaused
        initializedAndNonReentrant
        returns (uint256 validatedActions_)
    {
        return ActionsUtils.validateActionablePendingActions(s, previousActionsData, maxValidations);
    }

    /// @inheritdoc IUsdnProtocolActions
    function transferPositionOwnership(PositionId calldata posId, bytes calldata delegationSignature, address newOwner)
        external
        whenNotPaused
        initializedAndNonReentrant
    {
        return ActionsUtils.transferPositionOwnership(s, posId, delegationSignature, _domainSeparatorV4(), newOwner);
    }

    /// @inheritdoc IUsdnProtocolActions
    function tickHash(int24 tick, uint256 version) external pure returns (bytes32) {
        return Utils.tickHash(tick, version);
    }

    /// @inheritdoc IUsdnProtocolActions
    function getLongPosition(PositionId memory posId)
        external
        view
        returns (Position memory pos_, uint24 liquidationPenalty_)
    {
        return ActionsUtils.getLongPosition(s, posId);
    }
}

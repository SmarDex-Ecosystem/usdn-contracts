// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.25;

import { PositionId, PreviousActionsData } from "../interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import {
    InitiateClosePositionParams, InitiateOpenPositionParams
} from "../interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import { Permit2TokenBitfield } from "../libraries/Permit2TokenBitfield.sol";
import { IUsdnProtocolActions } from "./../interfaces/UsdnProtocol/IUsdnProtocolActions.sol";
import { UsdnProtocolStorage } from "./UsdnProtocolStorage.sol";
import { UsdnProtocolActionsLongLibrary as actionsLongLib } from "./libraries/UsdnProtocolActionsLongLibrary.sol";
import { UsdnProtocolActionsUtilsLibrary as actionsUtilsLib } from "./libraries/UsdnProtocolActionsUtilsLibrary.sol";
import { UsdnProtocolActionsVaultLibrary as actionsVaultLib } from "./libraries/UsdnProtocolActionsVaultLibrary.sol";

abstract contract UsdnProtocolActionsEntry is UsdnProtocolStorage, IUsdnProtocolActions {
    /// @inheritdoc IUsdnProtocolActions
    function initiateDeposit(
        uint128 amount,
        address to,
        address payable validator,
        Permit2TokenBitfield.Bitfield permit2TokenBitfield,
        bytes calldata currentPriceData,
        PreviousActionsData calldata previousActionsData
    ) external payable initializedAndNonReentrant returns (bool success_) {
        return actionsVaultLib.initiateDeposit(
            s, amount, to, validator, permit2TokenBitfield, currentPriceData, previousActionsData
        );
    }

    /// @inheritdoc IUsdnProtocolActions
    function validateDeposit(
        address payable validator,
        bytes calldata depositPriceData,
        PreviousActionsData calldata previousActionsData
    ) external payable initializedAndNonReentrant returns (bool success_) {
        return actionsVaultLib.validateDeposit(s, validator, depositPriceData, previousActionsData);
    }

    /// @inheritdoc IUsdnProtocolActions
    function initiateWithdrawal(
        uint152 usdnShares,
        address to,
        address payable validator,
        bytes calldata currentPriceData,
        PreviousActionsData calldata previousActionsData
    ) external payable initializedAndNonReentrant returns (bool success_) {
        return actionsVaultLib.initiateWithdrawal(s, usdnShares, to, validator, currentPriceData, previousActionsData);
    }

    /// @inheritdoc IUsdnProtocolActions
    function validateWithdrawal(
        address payable validator,
        bytes calldata withdrawalPriceData,
        PreviousActionsData calldata previousActionsData
    ) external payable initializedAndNonReentrant returns (bool success_) {
        return actionsVaultLib.validateWithdrawal(s, validator, withdrawalPriceData, previousActionsData);
    }

    /// @inheritdoc IUsdnProtocolActions
    function initiateOpenPosition(
        uint128 amount,
        uint128 desiredLiqPrice,
        address to,
        address payable validator,
        Permit2TokenBitfield.Bitfield permit2TokenBitfield,
        bytes calldata currentPriceData,
        PreviousActionsData calldata previousActionsData
    ) external payable initializedAndNonReentrant returns (bool success_, PositionId memory posId_) {
        InitiateOpenPositionParams memory params = InitiateOpenPositionParams({
            user: msg.sender,
            to: to,
            validator: validator,
            amount: amount,
            desiredLiqPrice: desiredLiqPrice,
            securityDepositValue: s._securityDepositValue,
            permit2TokenBitfield: permit2TokenBitfield
        });

        return actionsLongLib.initiateOpenPosition(s, params, currentPriceData, previousActionsData);
    }

    /// @inheritdoc IUsdnProtocolActions
    function validateOpenPosition(
        address payable validator,
        bytes calldata openPriceData,
        PreviousActionsData calldata previousActionsData
    ) external payable initializedAndNonReentrant returns (bool success_) {
        return actionsLongLib.validateOpenPosition(s, validator, openPriceData, previousActionsData);
    }

    /// @inheritdoc IUsdnProtocolActions
    function initiateClosePosition(
        PositionId calldata posId,
        uint128 amountToClose,
        address to,
        address payable validator,
        bytes calldata currentPriceData,
        PreviousActionsData calldata previousActionsData
    ) external payable initializedAndNonReentrant returns (bool success_) {
        InitiateClosePositionParams memory params =
            InitiateClosePositionParams({ posId: posId, amountToClose: amountToClose, to: to, validator: validator });

        return actionsLongLib.initiateClosePosition(s, params, currentPriceData, previousActionsData);
    }

    /// @inheritdoc IUsdnProtocolActions
    function validateClosePosition(
        address payable validator,
        bytes calldata closePriceData,
        PreviousActionsData calldata previousActionsData
    ) external payable initializedAndNonReentrant returns (bool success_) {
        return actionsLongLib.validateClosePosition(s, validator, closePriceData, previousActionsData);
    }

    /// @inheritdoc IUsdnProtocolActions
    function liquidate(bytes calldata currentPriceData, uint16 iterations)
        external
        payable
        initializedAndNonReentrant
        returns (uint256 liquidatedPositions_)
    {
        return actionsUtilsLib.liquidate(s, currentPriceData, iterations);
    }

    /// @inheritdoc IUsdnProtocolActions
    function validateActionablePendingActions(PreviousActionsData calldata previousActionsData, uint256 maxValidations)
        external
        payable
        initializedAndNonReentrant
        returns (uint256 validatedActions_)
    {
        return actionsUtilsLib.validateActionablePendingActions(s, previousActionsData, maxValidations);
    }

    /// @inheritdoc IUsdnProtocolActions
    function transferPositionOwnership(PositionId calldata posId, address newOwner)
        external
        initializedAndNonReentrant
    {
        return actionsUtilsLib.transferPositionOwnership(s, posId, newOwner);
    }

    /// @inheritdoc IUsdnProtocolActions
    function tickHash(int24 tick, uint256 version) external pure returns (bytes32) {
        return actionsLongLib.tickHash(tick, version);
    }
}

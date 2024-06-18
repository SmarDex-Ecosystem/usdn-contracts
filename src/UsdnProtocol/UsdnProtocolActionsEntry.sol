// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.25;

import { Permit2TokenBitfield } from "../libraries/Permit2TokenBitfield.sol";
import { UsdnProtocolActionsLibrary as lib } from "./UsdnProtocolActionsLibrary.sol";
import { UsdnProtocolBaseStorage } from "./UsdnProtocolBaseStorage.sol";
import { PreviousActionsData, PositionId } from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import { InitiateOpenPositionParams, InitiateClosePositionParams } from "./UsdnProtocolActionsLibrary.sol";

abstract contract UsdnProtocolActionsEntry is UsdnProtocolBaseStorage {
    function initiateDeposit(
        uint128 amount,
        address to,
        address payable validator,
        Permit2TokenBitfield.Bitfield permit2TokenBitfield,
        bytes calldata currentPriceData,
        PreviousActionsData calldata previousActionsData
    ) external payable returns (bool success_) {
        return
            lib.initiateDeposit(s, amount, to, validator, permit2TokenBitfield, currentPriceData, previousActionsData);
    }

    function validateDeposit(
        address payable validator,
        bytes calldata depositPriceData,
        PreviousActionsData calldata previousActionsData
    ) external payable returns (bool success_) {
        return lib.validateDeposit(s, validator, depositPriceData, previousActionsData);
    }

    function initiateWithdrawal(
        uint152 usdnShares,
        address to,
        address payable validator,
        bytes calldata currentPriceData,
        PreviousActionsData calldata previousActionsData
    ) external payable returns (bool success_) {
        return lib.initiateWithdrawal(s, usdnShares, to, validator, currentPriceData, previousActionsData);
    }

    function validateWithdrawal(
        address payable validator,
        bytes calldata withdrawalPriceData,
        PreviousActionsData calldata previousActionsData
    ) external payable returns (bool success_) {
        return lib.validateWithdrawal(s, validator, withdrawalPriceData, previousActionsData);
    }

    function initiateOpenPosition(
        uint128 amount,
        uint128 desiredLiqPrice,
        address to,
        address payable validator,
        Permit2TokenBitfield.Bitfield permit2TokenBitfield,
        bytes calldata currentPriceData,
        PreviousActionsData calldata previousActionsData
    ) external payable returns (bool success_, PositionId memory posId_) {
        InitiateOpenPositionParams memory params = InitiateOpenPositionParams({
            user: msg.sender,
            to: to,
            validator: validator,
            amount: amount,
            desiredLiqPrice: desiredLiqPrice,
            securityDepositValue: s._securityDepositValue,
            permit2TokenBitfield: permit2TokenBitfield
        });

        return lib.initiateOpenPosition(s, params, currentPriceData, previousActionsData);
    }

    function validateOpenPosition(
        address payable validator,
        bytes calldata openPriceData,
        PreviousActionsData calldata previousActionsData
    ) external payable returns (bool success_) {
        return lib.validateOpenPosition(s, validator, openPriceData, previousActionsData);
    }

    function initiateClosePosition(
        PositionId calldata posId,
        uint128 amountToClose,
        address to,
        address payable validator,
        bytes calldata currentPriceData,
        PreviousActionsData calldata previousActionsData
    ) external payable returns (bool success_) {
        InitiateClosePositionParams memory params =
            InitiateClosePositionParams({ posId: posId, amountToClose: amountToClose, to: to, validator: validator });

        return lib.initiateClosePosition(s, params, currentPriceData, previousActionsData);
    }

    function validateClosePosition(
        address payable validator,
        bytes calldata closePriceData,
        PreviousActionsData calldata previousActionsData
    ) external payable returns (bool success_) {
        return lib.validateClosePosition(s, validator, closePriceData, previousActionsData);
    }

    function liquidate(bytes calldata currentPriceData, uint16 iterations)
        external
        payable
        returns (uint256 liquidatedPositions_)
    {
        return lib.liquidate(s, currentPriceData, iterations);
    }

    function validateActionablePendingActions(PreviousActionsData calldata previousActionsData, uint256 maxValidations)
        external
        payable
        returns (uint256 validatedActions_)
    {
        return lib.validateActionablePendingActions(s, previousActionsData, maxValidations);
    }

    function transferPositionOwnership(PositionId calldata posId, address newOwner) external {
        return lib.transferPositionOwnership(s, posId, newOwner);
    }

    function _checkImbalanceLimitDeposit(uint256 depositValue) internal view {
        return lib._checkImbalanceLimitDeposit(s, depositValue);
    }
}

// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import { IUsdnProtocolActions } from "../interfaces/UsdnProtocol/IUsdnProtocolActions.sol";
import { Permit2TokenBitfield } from "../libraries/Permit2TokenBitfield.sol";
import { UsdnProtocolStorage } from "./UsdnProtocolStorage.sol";
import { UsdnProtocolActionsLongLibrary as ActionsLong } from "./libraries/UsdnProtocolActionsLongLibrary.sol";
import { UsdnProtocolActionsUtilsLibrary as ActionsUtils } from "./libraries/UsdnProtocolActionsUtilsLibrary.sol";
import { UsdnProtocolActionsVaultLibrary as ActionsVault } from "./libraries/UsdnProtocolActionsVaultLibrary.sol";
import { UsdnProtocolUtilsLibrary as Utils } from "./libraries/UsdnProtocolUtilsLibrary.sol";

abstract contract UsdnProtocolActions is UsdnProtocolStorage, IUsdnProtocolActions {
    /// @inheritdoc IUsdnProtocolActions
    function initiateDeposit(
        uint128 amount,
        address to,
        address payable validator,
        Permit2TokenBitfield.Bitfield permit2TokenBitfield,
        bytes calldata currentPriceData,
        PreviousActionsData calldata previousActionsData
    ) external payable initializedAndNonReentrant returns (bool success_) {
        return ActionsVault.initiateDeposit(
            s, amount, to, validator, permit2TokenBitfield, currentPriceData, previousActionsData
        );
    }

    /// @inheritdoc IUsdnProtocolActions
    function validateDeposit(
        address payable validator,
        bytes calldata depositPriceData,
        PreviousActionsData calldata previousActionsData
    ) external payable initializedAndNonReentrant returns (bool success_) {
        return ActionsVault.validateDeposit(s, validator, depositPriceData, previousActionsData);
    }

    /// @inheritdoc IUsdnProtocolActions
    function initiateWithdrawal(
        uint152 usdnShares,
        address to,
        address payable validator,
        bytes calldata currentPriceData,
        PreviousActionsData calldata previousActionsData
    ) external payable initializedAndNonReentrant returns (bool success_) {
        return ActionsVault.initiateWithdrawal(s, usdnShares, to, validator, currentPriceData, previousActionsData);
    }

    /// @inheritdoc IUsdnProtocolActions
    function validateWithdrawal(
        address payable validator,
        bytes calldata withdrawalPriceData,
        PreviousActionsData calldata previousActionsData
    ) external payable initializedAndNonReentrant returns (bool success_) {
        return ActionsVault.validateWithdrawal(s, validator, withdrawalPriceData, previousActionsData);
    }

    /// @inheritdoc IUsdnProtocolActions
    function initiateOpenPosition(
        uint128 amount,
        uint128 desiredLiqPrice,
        uint256 userMaxLeverage,
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
            userMaxLeverage: userMaxLeverage,
            securityDepositValue: s._securityDepositValue,
            permit2TokenBitfield: permit2TokenBitfield
        });

        return ActionsLong.initiateOpenPosition(s, params, currentPriceData, previousActionsData);
    }

    /// @inheritdoc IUsdnProtocolActions
    function validateOpenPosition(
        address payable validator,
        bytes calldata openPriceData,
        PreviousActionsData calldata previousActionsData
    ) external payable initializedAndNonReentrant returns (bool success_) {
        return ActionsLong.validateOpenPosition(s, validator, openPriceData, previousActionsData);
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

        return ActionsLong.initiateClosePosition(s, params, currentPriceData, previousActionsData);
    }

    /// @inheritdoc IUsdnProtocolActions
    function validateClosePosition(
        address payable validator,
        bytes calldata closePriceData,
        PreviousActionsData calldata previousActionsData
    ) external payable initializedAndNonReentrant returns (bool success_) {
        return ActionsLong.validateClosePosition(s, validator, closePriceData, previousActionsData);
    }

    /// @inheritdoc IUsdnProtocolActions
    function liquidate(bytes calldata currentPriceData, uint16 iterations)
        external
        payable
        initializedAndNonReentrant
        returns (uint256 liquidatedPositions_)
    {
        return ActionsUtils.liquidate(s, currentPriceData, iterations);
    }

    /// @inheritdoc IUsdnProtocolActions
    function validateActionablePendingActions(PreviousActionsData calldata previousActionsData, uint256 maxValidations)
        external
        payable
        initializedAndNonReentrant
        returns (uint256 validatedActions_)
    {
        return ActionsUtils.validateActionablePendingActions(s, previousActionsData, maxValidations);
    }

    /// @inheritdoc IUsdnProtocolActions
    function transferPositionOwnership(PositionId calldata posId, address newOwner)
        external
        initializedAndNonReentrant
    {
        return ActionsUtils.transferPositionOwnership(s, posId, newOwner);
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

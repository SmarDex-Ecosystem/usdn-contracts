// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import { ReentrancyGuardTransientUpgradeable } from
    "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardTransientUpgradeable.sol";
import { EIP712Upgradeable } from "@openzeppelin/contracts-upgradeable/utils/cryptography/EIP712Upgradeable.sol";

import { IUsdnProtocolActions } from "../interfaces/UsdnProtocol/IUsdnProtocolActions.sol";
import { InitializableReentrancyGuard } from "../utils/InitializableReentrancyGuard.sol";
import { UsdnProtocolActionsLongLibrary as ActionsLong } from "./libraries/UsdnProtocolActionsLongLibrary.sol";
import { UsdnProtocolActionsUtilsLibrary as ActionsUtils } from "./libraries/UsdnProtocolActionsUtilsLibrary.sol";
import { UsdnProtocolUtilsLibrary as Utils } from "./libraries/UsdnProtocolUtilsLibrary.sol";
import { UsdnProtocolVaultLibrary as Vault } from "./libraries/UsdnProtocolVaultLibrary.sol";

abstract contract UsdnProtocolActions is
    IUsdnProtocolActions,
    InitializableReentrancyGuard,
    ReentrancyGuardTransientUpgradeable,
    PausableUpgradeable,
    EIP712Upgradeable
{
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
    )
        external
        payable
        whenNotPaused
        initializedAndNonReentrant
        nonReentrant
        returns (bool success_, PositionId memory posId_)
    {
        Storage storage s = Utils._getMainStorage();

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

        return ActionsLong.initiateOpenPosition(params, currentPriceData, previousActionsData);
    }

    /// @inheritdoc IUsdnProtocolActions
    function validateOpenPosition(
        address payable validator,
        bytes calldata openPriceData,
        PreviousActionsData calldata previousActionsData
    ) external payable whenNotPaused initializedAndNonReentrant nonReentrant returns (bool success_) {
        return ActionsLong.validateOpenPosition(validator, openPriceData, previousActionsData);
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
    ) external payable whenNotPaused initializedAndNonReentrant nonReentrant returns (bool success_) {
        Storage storage s = Utils._getMainStorage();

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

        return ActionsLong.initiateClosePosition(params, currentPriceData, previousActionsData, delegationSignature);
    }

    /// @inheritdoc IUsdnProtocolActions
    function validateClosePosition(
        address payable validator,
        bytes calldata closePriceData,
        PreviousActionsData calldata previousActionsData
    ) external payable whenNotPaused initializedAndNonReentrant nonReentrant returns (bool success_) {
        return ActionsLong.validateClosePosition(validator, closePriceData, previousActionsData);
    }

    /// @inheritdoc IUsdnProtocolActions
    function initiateDeposit(
        uint128 amount,
        uint256 sharesOutMin,
        address to,
        address payable validator,
        uint256 deadline,
        bytes calldata currentPriceData,
        PreviousActionsData calldata previousActionsData
    ) external payable whenNotPaused initializedAndNonReentrant nonReentrant returns (bool success_) {
        return
            Vault.initiateDeposit(amount, sharesOutMin, to, validator, deadline, currentPriceData, previousActionsData);
    }

    /// @inheritdoc IUsdnProtocolActions
    function validateDeposit(
        address payable validator,
        bytes calldata depositPriceData,
        PreviousActionsData calldata previousActionsData
    ) external payable whenNotPaused initializedAndNonReentrant nonReentrant returns (bool success_) {
        return Vault.validateDeposit(validator, depositPriceData, previousActionsData);
    }

    /// @inheritdoc IUsdnProtocolActions
    function initiateWithdrawal(
        uint152 usdnShares,
        uint256 amountOutMin,
        address to,
        address payable validator,
        uint256 deadline,
        bytes calldata currentPriceData,
        PreviousActionsData calldata previousActionsData
    ) external payable whenNotPaused initializedAndNonReentrant nonReentrant returns (bool success_) {
        return Vault.initiateWithdrawal(
            usdnShares, amountOutMin, to, validator, deadline, currentPriceData, previousActionsData
        );
    }

    /// @inheritdoc IUsdnProtocolActions
    function validateWithdrawal(
        address payable validator,
        bytes calldata withdrawalPriceData,
        PreviousActionsData calldata previousActionsData
    ) external payable whenNotPaused initializedAndNonReentrant nonReentrant returns (bool success_) {
        return Vault.validateWithdrawal(validator, withdrawalPriceData, previousActionsData);
    }

    /// @inheritdoc IUsdnProtocolActions
    function liquidate(bytes calldata currentPriceData)
        external
        payable
        whenNotPaused
        initializedAndNonReentrant
        nonReentrant
        returns (LiqTickInfo[] memory liquidatedTicks_)
    {
        return ActionsUtils.liquidate(currentPriceData);
    }

    /// @inheritdoc IUsdnProtocolActions
    function validateActionablePendingActions(PreviousActionsData calldata previousActionsData, uint256 maxValidations)
        external
        payable
        whenNotPaused
        initializedAndNonReentrant
        nonReentrant
        returns (uint256 validatedActions_)
    {
        return ActionsUtils.validateActionablePendingActions(previousActionsData, maxValidations);
    }

    /// @inheritdoc IUsdnProtocolActions
    function transferPositionOwnership(PositionId calldata posId, address newOwner, bytes calldata delegationSignature)
        external
        whenNotPaused
        initializedAndNonReentrant
        nonReentrant
    {
        return ActionsUtils.transferPositionOwnership(posId, newOwner, delegationSignature, _domainSeparatorV4());
    }

    /// @inheritdoc IUsdnProtocolActions
    function domainSeparatorV4() external view returns (bytes32) {
        return _domainSeparatorV4();
    }
}

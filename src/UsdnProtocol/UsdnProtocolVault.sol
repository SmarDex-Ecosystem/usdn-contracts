// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import { IUsdnProtocolVault } from "../interfaces/UsdnProtocol/IUsdnProtocolVault.sol";
import { UsdnProtocolStorage } from "./UsdnProtocolStorage.sol";
import { UsdnProtocolVaultLibrary as Vault } from "./libraries/UsdnProtocolVaultLibrary.sol";

abstract contract UsdnProtocolVault is UsdnProtocolStorage, IUsdnProtocolVault {
    /// @inheritdoc IUsdnProtocolVault
    function initiateDeposit(
        uint128 amount,
        uint256 sharesOutMin,
        address to,
        address payable validator,
        bytes calldata currentPriceData,
        PreviousActionsData calldata previousActionsData
    ) external payable initializedAndNonReentrant returns (bool success_) {
        return Vault.initiateDeposit(s, amount, sharesOutMin, to, validator, currentPriceData, previousActionsData);
    }

    /// @inheritdoc IUsdnProtocolVault
    function validateDeposit(
        address payable validator,
        bytes calldata depositPriceData,
        PreviousActionsData calldata previousActionsData
    ) external payable initializedAndNonReentrant returns (bool success_) {
        return Vault.validateDeposit(s, validator, depositPriceData, previousActionsData);
    }

    /// @inheritdoc IUsdnProtocolVault
    function initiateWithdrawal(
        uint152 usdnShares,
        uint256 amountOutMin,
        address to,
        address payable validator,
        bytes calldata currentPriceData,
        PreviousActionsData calldata previousActionsData
    ) external payable initializedAndNonReentrant returns (bool success_) {
        return
            Vault.initiateWithdrawal(s, usdnShares, amountOutMin, to, validator, currentPriceData, previousActionsData);
    }

    /// @inheritdoc IUsdnProtocolVault
    function validateWithdrawal(
        address payable validator,
        bytes calldata withdrawalPriceData,
        PreviousActionsData calldata previousActionsData
    ) external payable initializedAndNonReentrant returns (bool success_) {
        return Vault.validateWithdrawal(s, validator, withdrawalPriceData, previousActionsData);
    }

    /// @inheritdoc IUsdnProtocolVault
    function getActionablePendingActions(address currentUser)
        external
        view
        returns (PendingAction[] memory actions_, uint128[] memory rawIndices_)
    {
        return Vault.getActionablePendingActions(s, currentUser);
    }

    /// @inheritdoc IUsdnProtocolVault
    function usdnPrice(uint128 currentPrice, uint128 timestamp) external view returns (uint256 price_) {
        return Vault.usdnPrice(s, currentPrice, timestamp);
    }

    /// @inheritdoc IUsdnProtocolVault
    function usdnPrice(uint128 currentPrice) external view returns (uint256 price_) {
        return Vault.usdnPrice(s, currentPrice);
    }

    /// @inheritdoc IUsdnProtocolVault
    function vaultAssetAvailableWithFunding(uint128 currentPrice, uint128 timestamp)
        external
        view
        returns (int256 available_)
    {
        return Vault.vaultAssetAvailableWithFunding(s, currentPrice, timestamp);
    }
}

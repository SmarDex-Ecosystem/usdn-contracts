// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

import { IUsdnProtocolVault } from "../interfaces/UsdnProtocol/IUsdnProtocolVault.sol";
import { InitializableReentrancyGuard } from "../utils/InitializableReentrancyGuard.sol";
import { UsdnProtocolVaultLibrary as Vault } from "./libraries/UsdnProtocolVaultLibrary.sol";

abstract contract UsdnProtocolVault is IUsdnProtocolVault, InitializableReentrancyGuard, PausableUpgradeable {
    /// @inheritdoc IUsdnProtocolVault
    function usdnPrice(uint128 currentPrice, uint128 timestamp) external view returns (uint256 price_) {
        return Vault.usdnPrice(currentPrice, timestamp);
    }

    /// @inheritdoc IUsdnProtocolVault
    function usdnPrice(uint128 currentPrice) external view returns (uint256 price_) {
        return Vault.usdnPrice(currentPrice);
    }

    /// @inheritdoc IUsdnProtocolVault
    function vaultAssetAvailableWithFunding(uint128 currentPrice, uint128 timestamp)
        external
        view
        returns (uint256 available_)
    {
        return Vault.vaultAssetAvailableWithFunding(currentPrice, timestamp);
    }
}

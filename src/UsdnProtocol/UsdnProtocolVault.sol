// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import { IUsdnProtocolVault } from "../interfaces/UsdnProtocol/IUsdnProtocolVault.sol";
import { UsdnProtocolStorage } from "./UsdnProtocolStorage.sol";
import { UsdnProtocolVaultLibrary as Vault } from "./libraries/UsdnProtocolVaultLibrary.sol";

abstract contract UsdnProtocolVault is UsdnProtocolStorage, IUsdnProtocolVault {
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

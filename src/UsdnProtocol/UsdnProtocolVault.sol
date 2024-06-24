// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.25;

import { IUsdnProtocolVault } from "../interfaces/UsdnProtocol/IUsdnProtocolVault.sol";
import { UsdnProtocolStorage } from "./UsdnProtocolStorage.sol";
import { UsdnProtocolVaultLibrary as lib } from "./libraries/UsdnProtocolVaultLibrary.sol";

abstract contract UsdnProtocolVault is UsdnProtocolStorage, IUsdnProtocolVault {
    /// @inheritdoc IUsdnProtocolVault
    function usdnPrice(uint128 currentPrice, uint128 timestamp) external view returns (uint256 price_) {
        return lib.usdnPrice(s, currentPrice, timestamp);
    }

    /// @inheritdoc IUsdnProtocolVault
    function usdnPrice(uint128 currentPrice) external view returns (uint256 price_) {
        return lib.usdnPrice(s, currentPrice);
    }

    /// @inheritdoc IUsdnProtocolVault
    function previewDeposit(uint256 amount, uint128 price, uint128 timestamp)
        external
        view
        returns (uint256 usdnSharesExpected_, uint256 sdexToBurn_)
    {
        return lib.previewDeposit(s, amount, price, timestamp);
    }

    /// @inheritdoc IUsdnProtocolVault
    function previewWithdraw(uint256 usdnShares, uint256 price, uint128 timestamp)
        external
        view
        returns (uint256 assetExpected_)
    {
        return lib.previewWithdraw(s, usdnShares, price, timestamp);
    }

    /// @inheritdoc IUsdnProtocolVault
    function vaultAssetAvailableWithFunding(uint128 currentPrice, uint128 timestamp)
        external
        view
        returns (int256 available_)
    {
        return lib.vaultAssetAvailableWithFunding(s, currentPrice, timestamp);
    }
}

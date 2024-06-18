// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.25;

import { UsdnProtocolBaseStorage } from "./UsdnProtocolBaseStorage.sol";
import { UsdnProtocolVaultLibrary as lib } from "./UsdnProtocolVaultLibrary.sol";

abstract contract UsdnProtocolVaultEntry is UsdnProtocolBaseStorage {
    function usdnPrice(uint128 currentPrice, uint128 timestamp) public view returns (uint256 price_) {
        return lib.usdnPrice(s, currentPrice, timestamp);
    }

    function usdnPrice(uint128 currentPrice) external view returns (uint256 price_) {
        return lib.usdnPrice(s, currentPrice);
    }

    function previewDeposit(uint256 amount, uint128 price, uint128 timestamp)
        external
        view
        returns (uint256 usdnSharesExpected_, uint256 sdexToBurn_)
    {
        return lib.previewDeposit(s, amount, price, timestamp);
    }

    function previewWithdraw(uint256 usdnShares, uint256 price, uint128 timestamp)
        external
        view
        returns (uint256 assetExpected_)
    {
        return lib.previewWithdraw(s, usdnShares, price, timestamp);
    }

    function vaultAssetAvailableWithFunding(uint128 currentPrice, uint128 timestamp)
        public
        view
        returns (int256 available_)
    {
        return lib.vaultAssetAvailableWithFunding(s, currentPrice, timestamp);
    }

    // / @inheritdoc IUsdnProtocol
    function removeBlockedPendingAction(address validator, address payable to) external onlyOwner {
        lib.removeBlockedPendingAction(s, validator, to);
    }

    // / @inheritdoc IUsdnProtocol
    function removeBlockedPendingActionNoCleanup(address validator, address payable to) external onlyOwner {
        lib.removeBlockedPendingActionNoCleanup(s, validator, to);
    }
}

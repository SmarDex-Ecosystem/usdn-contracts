// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { UsdnProtocolStorage } from "src/UsdnProtocol/UsdnProtocolStorage.sol";
import { IUsdnProtocolErrors } from "src/interfaces/UsdnProtocol/IUsdnProtocol.sol";

abstract contract UsdnProtocolCore is IUsdnProtocolErrors, UsdnProtocolStorage {
    using SafeERC20 for IERC20Metadata;

    function _retrieveAssetsAndCheckBalance(address _from, uint256 _amount) internal {
        uint256 _balanceBefore = asset.balanceOf(address(this));
        asset.safeTransferFrom(_from, address(this), _amount);
        if (asset.balanceOf(address(this)) != _balanceBefore + _amount) {
            revert UsdnProtocolIncompleteTransfer(asset.balanceOf(address(this)), _balanceBefore + _amount);
        }
    }

    function _applyPnlAndFunding(uint128 _currentPrice, uint128 _timestamp) internal {
        // If the price is not fresh, do nothing
        if (_timestamp <= lastUpdateTimestamp) {
            return;
        }
        // silence unused variable and visibility warnings
        _currentPrice;
        balanceVault = balanceVault;
        // TODO: apply PnL and funding
    }
}

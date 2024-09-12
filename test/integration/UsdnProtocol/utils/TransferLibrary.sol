// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { ERC165, IERC165 } from "@openzeppelin/contracts/utils/introspection/ERC165.sol";

import { UsdnProtocolConstantsLibrary as Constants } from
    "../../../../src/UsdnProtocol/libraries/UsdnProtocolConstantsLibrary.sol";
import { IRouterFallback } from "../../../../src/interfaces/IRouterFallback.sol";

abstract contract TransferLibrary is IRouterFallback, ERC165 {
    bool public assetActive;
    bool public sdexActive;

    /// @inheritdoc IRouterFallback
    function transferSdexCallback(IERC20Metadata sdex, uint256 amount) external {
        if (sdexActive) {
            sdex.transfer(Constants.DEAD_ADDRESS, amount);
        }
    }

    /// @inheritdoc IRouterFallback
    function transferAssetCallback(IERC20Metadata asset, uint256 amount) external {
        if (assetActive) {
            asset.transfer(msg.sender, amount);
        }
    }

    /// @inheritdoc ERC165
    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC165, IERC165) returns (bool) {
        if (interfaceId == type(IRouterFallback).interfaceId) {
            return true;
        }

        return super.supportsInterface(interfaceId);
    }
}

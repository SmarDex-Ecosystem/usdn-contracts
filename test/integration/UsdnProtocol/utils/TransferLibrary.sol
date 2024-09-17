// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { ERC165, IERC165 } from "@openzeppelin/contracts/utils/introspection/ERC165.sol";

import { IRouterFallback } from "../../../../src/interfaces/IRouterFallback.sol";

abstract contract TransferLibrary is IRouterFallback, ERC165 {
    bool public transferActive;

    /// @inheritdoc IRouterFallback
    function transferWithFallback(IERC20Metadata token, uint256 amount, address to) external {
        if (transferActive) {
            token.transfer(to, amount);
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

// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { ERC165, IERC165 } from "@openzeppelin/contracts/utils/introspection/ERC165.sol";

import { IPaymentCallback, IUsdn } from "../../../../src/interfaces/UsdnProtocol/IPaymentCallback.sol";

abstract contract TransferCallback is IPaymentCallback, ERC165 {
    bool public transferActive;

    /// @inheritdoc IPaymentCallback
    function transferCallback(IERC20Metadata token, uint256 amount, address to) external virtual {
        if (transferActive) {
            token.transfer(to, amount);
        }
    }

    /// @inheritdoc IPaymentCallback
    function usdnTransferCallback(IUsdn usdn, uint256 shares) external {
        if (transferActive) {
            usdn.transferShares(msg.sender, shares);
        }
    }

    /// @inheritdoc ERC165
    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC165, IERC165) returns (bool) {
        if (interfaceId == type(IPaymentCallback).interfaceId) {
            return true;
        }

        return super.supportsInterface(interfaceId);
    }
}

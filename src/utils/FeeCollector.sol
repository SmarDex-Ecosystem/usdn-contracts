// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { ERC165 } from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import { IERC165 } from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

import { IFeeCollectorCallback } from "./../interfaces/UsdnProtocol/IFeeCollectorCallback.sol";

/**
 * @title FeeCollector
 * @dev Minimum implementation of the fee collector contract
 */
contract FeeCollector is IFeeCollectorCallback, ERC165 {
    /// @inheritdoc ERC165
    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC165, IERC165) returns (bool) {
        if (interfaceId == type(IFeeCollectorCallback).interfaceId) {
            return true;
        }

        return super.supportsInterface(interfaceId);
    }

    /// @inheritdoc IFeeCollectorCallback
    function feeCollectorCallback(uint256 feeAmount) external virtual { }
}

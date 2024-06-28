// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { ERC165 } from "@openzeppelin/contracts/utils/introspection/ERC165.sol";

import { IFeeCollector } from "./../interfaces/UsdnProtocol/IFeeCollector.sol";
import { IFeeCollectorCallback } from "./../interfaces/UsdnProtocol/IFeeCollectorCallback.sol";

/**
 * @title FeeCollector
 * @dev Minimum implementation of the fee collector contract
 */
contract FeeCollector is IFeeCollector, ERC165 {
    /// @inheritdoc ERC165
    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC165, IFeeCollector) returns (bool) {
        if (interfaceId == type(IFeeCollector).interfaceId) {
            return true;
        }
        if (interfaceId == type(IFeeCollectorCallback).interfaceId) {
            return true;
        }

        return super.supportsInterface(interfaceId);
    }

    /// @inheritdoc IFeeCollector
    function feeCollectorCallback(uint256 feeAmount) external virtual { }
}

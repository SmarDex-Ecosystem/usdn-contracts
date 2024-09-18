// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { IERC165 } from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

/**
 * @notice This interface can be implemented by contracts that wish to transfer tokens during initiate actions
 * @dev The contract must implement the ERC-165 interface detection mechanism
 */
interface IPaymentCallback is IERC165 {
    /**
     * @notice Callback function to be called during initiate functions to transfer asset tokens
     * @param token The token to transfer
     * @param amount The amount to transfer
     * @param to The address to transfer
     */
    function transferCallback(IERC20Metadata token, uint256 amount, address to) external;
}

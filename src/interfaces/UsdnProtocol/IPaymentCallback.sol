// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { IERC165 } from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

import { IUsdn } from "../Usdn/IUsdn.sol";

/**
 * @notice This interface can be implemented by contracts that wish to transfer tokens during initiate actions
 * @dev The contract must implement the ERC-165 interface detection mechanism
 */
interface IPaymentCallback is IERC165 {
    /**
     * @notice Callback function to be called during initiate functions to transfer asset tokens
     * @dev The implementation must ensure that the `msg.sender` is the protocol contract
     * @param token The token to transfer
     * @param amount The amount to transfer
     * @param to The address of the recipient
     */
    function transferCallback(IERC20Metadata token, uint256 amount, address to) external;

    /**
     * @notice Callback function to be called during `initiateWithdrawal` to transfer USDN shares to the protocol
     * @dev The implementation must ensure that the `msg.sender` is the protocol contract
     * @param usdn The USDN contract address
     * @param shares The amount of USDN shares to transfer to the `msg.sender`
     */
    function usdnTransferCallback(IUsdn usdn, uint256 shares) external;
}

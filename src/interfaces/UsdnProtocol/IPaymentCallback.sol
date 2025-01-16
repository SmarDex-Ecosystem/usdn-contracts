// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { IERC165 } from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

import { IUsdn } from "../Usdn/IUsdn.sol";

/**
 * @notice This interface can be implemented by contracts that wish to transfer tokens during initiate actions.
 * @dev The contract must implement the ERC-165 interface detection mechanism.
 */
interface IPaymentCallback is IERC165 {
    /**
     * @notice Triggered by the USDN protocol to transfer asset tokens during `initiate` actions.
     * @dev Implementations must ensure that the `msg.sender` is the USDN protocol for security purposes.
     * @param token The address of the ERC20 token to be transferred.
     * @param amount The amount of tokens to transfer.
     * @param to The recipient's address.
     */
    function transferCallback(IERC20Metadata token, uint256 amount, address to) external;

    /**
     * @notice Triggered by the USDN protocol during the {IUsdnProtocolActions.initiateWithdrawal} process to transfer
     * USDN shares.
     * @dev Implementations must verify that the `msg.sender` is the USDN protocol.
     * @param usdn The address of the USDN protocol.
     * @param shares The number of USDN shares to transfer to the protocol (`msg.sender`).
     */
    function usdnTransferCallback(IUsdn usdn, uint256 shares) external;
}

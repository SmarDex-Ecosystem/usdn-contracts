// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

/**
 * @title Errors for the USDN token contract
 * @notice Defines all custom errors emitted by the USDN token contract.
 */
interface IUsdnErrors {
    /**
     * @dev The amount of tokens exceeds the maximum allowed limit.
     * @param value The invalid token value.
     */
    error UsdnMaxTokensExceeded(uint256 value);

    /**
     * @dev The sender's share balance is insufficient.
     * @param sender The sender's address.
     * @param balance The current share balance of the sender.
     * @param needed The required amount of shares for the transfer.
     */
    error UsdnInsufficientSharesBalance(address sender, uint256 balance, uint256 needed);

    /// @dev The divisor value in storage is invalid (< 1).
    error UsdnInvalidDivisor();
}

// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

/**
 * @title Errors for the USDN token contract
 * @notice Contains all custom errors emitted by the USDN token contract (omitting errors from OpenZeppelin)
 */
interface IUsdnErrors {
    /**
     * @dev Indicates that the number of tokens exceeds the maximum allowed value
     * @param value The invalid token value
     */
    error UsdnMaxTokensExceeded(uint256 value);

    /**
     * @dev Indicates that the sender does not have enough balance to transfer shares
     * @param sender The sender's address
     * @param balance The shares balance of the sender
     * @param needed The desired amount of shares to transfer
     */
    error UsdnInsufficientSharesBalance(address sender, uint256 balance, uint256 needed);

    /// @dev Indicates that the divisor value in storage is invalid
    error UsdnInvalidDivisor();
}

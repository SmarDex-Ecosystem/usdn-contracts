// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

/**
 * @title Errors for the USDN token contract
 * @notice Contains all custom errors emitted by the USDN token contract (omitting errors from OpenZeppelin)
 */
interface IUsdnErrors {
    /**
     * @dev Indicates that the provided divisor is invalid. This is usually because the new value is larger or
     * equal to the current divisor, or the new divisor is too small.
     * @param divisor invalid divisor
     */
    error UsdnInvalidDivisor(uint256 divisor);

    /**
     * @dev Indicates that the number of tokens exceeds the maximum allowed value.
     * @param value invalid token value
     */
    error UsdnMaxTokensExceeded(uint256 value);

    /// @dev Indicates that the newly minted tokens would make the total supply of shares overflow uint256
    error UsdnTotalSupplyOverflow();
}

// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { IERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";

/**
 * @title Events for the USDN token contract
 */
interface IUsdnEvents {
    /**
     * @notice Emitted when the divisor is adjusted.
     * @param oldDivisor divisor before adjustment
     * @param newDivisor divisor after adjustment
     */
    event DivisorAdjusted(uint256 oldDivisor, uint256 newDivisor);
}

/**
 * @title Errors for the USDN token contract
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

/**
 * @title USDN token interface
 * @notice Implements the ERC-20 token standard as well as the EIP-2612 permit extension. Additional functions related
 * to the specifics of this token are included below.
 */
interface IUsdn is IERC20, IERC20Metadata, IERC20Permit, IUsdnEvents, IUsdnErrors {
    /**
     * @notice Total number of shares in existence.
     * @return shares the number of shares
     */
    function totalShares() external view returns (uint256 shares);

    /**
     * @notice Number of shares owned by `account`.
     * @param account the account to query
     * @return shares the number of shares
     */
    function sharesOf(address account) external view returns (uint256 shares);

    /**
     * @notice Restricted function to mint new shares, providing a token value.
     * @dev Caller must have the MINTER_ROLE.
     * @param to account to receive the new shares
     * @param amount amount of tokens to mint, is internally converted to the proper shares amounts
     */
    function mint(address to, uint256 amount) external;

    /**
     * @notice Destroy a `value` amount of tokens from the caller, reducing the total supply.
     * @param value amount of tokens to burn, is internally converted to the proper shares amounts
     */
    function burn(uint256 value) external;

    /**
     * @notice Destroy a `value` amount of tokens from `account`, deducting from the caller's allowance.
     * @param account account to burn tokens from
     * @param value amount of tokens to burn, is internally converted to the proper shares amounts
     */
    function burnFrom(address account, uint256 value) external;

    /**
     * @notice Convert a number of tokens to the corresponding amount of shares.
     * @dev The conversion reverts with `UsdnMaxTokensExceeded` if the corresponding amount of shares would overflow.
     * @param amountTokens the amount of tokens to convert to shares
     * @return shares_ the corresponding amount of shares
     */
    function convertToShares(uint256 amountTokens) external view returns (uint256 shares_);

    /**
     * @notice Convert a number of shares to the corresponding amount of tokens.
     * @dev The conversion never overflows as we are performing a division. The conversion rounds to the nearest amount
     * of tokens that minimizes the error when converting back to shares.
     * @param amountShares the amount of shares to convert to tokens
     * @return tokens_ the corresponding amount of tokens
     */
    function convertToTokens(uint256 amountShares) external view returns (uint256 tokens_);

    /**
     * @notice View function returning the current maximum tokens supply, given the current divisor.
     * @dev This function is used to check if a conversion operation would overflow.
     * @return maxTokens_ the maximum number of tokens that can exist
     */
    function maxTokens() external view returns (uint256 maxTokens_);

    /**
     * @notice Restricted function to decrease the global divisor, which effectively grows all balances and the total
     * supply.
     * @param divisor the new divisor, must be strictly smaller than the current one
     */
    function adjustDivisor(uint256 divisor) external;

    /* -------------------------------------------------------------------------- */
    /*                             Dev view functions                             */
    /* -------------------------------------------------------------------------- */

    /// @dev The current value of the divisor that converts between tokens and shares.
    function divisor() external view returns (uint256);

    /// @dev Minter role signature.
    function MINTER_ROLE() external pure returns (bytes32);

    /// @dev Adjustment role signature.
    function ADJUSTMENT_ROLE() external pure returns (bytes32);

    /// @dev Maximum value of the divisor, which is also the intitial value.
    function MAX_DIVISOR() external pure returns (uint256);

    /// @dev Minimum acceptable value of the divisor.
    function MIN_DIVISOR() external pure returns (uint256);
}

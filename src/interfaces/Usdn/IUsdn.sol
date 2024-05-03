// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.0;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { IERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";

import { IUsdnEvents } from "src/interfaces/Usdn/IUsdnEvents.sol";
import { IUsdnErrors } from "src/interfaces/Usdn/IUsdnErrors.sol";

/**
 * @title USDN token interface
 * @notice Implements the ERC-20 token standard as well as the EIP-2612 permit extension. Additional functions related
 * to the specifics of this token are included below
 */
interface IUsdn is IERC20, IERC20Metadata, IERC20Permit, IUsdnEvents, IUsdnErrors {
    /**
     * @notice Total number of shares in existence
     * @return shares The number of shares
     */
    function totalShares() external view returns (uint256 shares);

    /**
     * @notice Number of shares owned by `account`
     * @param account The account to query
     * @return shares The number of shares
     */
    function sharesOf(address account) external view returns (uint256 shares);

    /**
     * @notice Transfer a given amount of shares from the `msg.sender` to `to`
     * @param to Recipient of the shares
     * @param value Number of shares to transfer
     * @return `true` in case of success
     */
    function transferShares(address to, uint256 value) external returns (bool);

    /**
     * @notice Transfer a given amount of shares from the `from` to `to`
     * @dev There should be sufficient allowance for the spender
     * @param from Owner of the shares
     * @param to Recipient of the shares
     * @param value Number of shares to transfer
     * @return `true` in case of success
     */
    function transferSharesFrom(address from, address to, uint256 value) external returns (bool);

    /**
     * @notice Restricted function to mint new shares, providing a token value
     * @dev Caller must have the MINTER_ROLE
     * @param to Account to receive the new shares
     * @param amount Amount of tokens to mint, is internally converted to the proper shares amounts
     */
    function mint(address to, uint256 amount) external;

    /**
     * @notice Restricted function to mint new shares
     * @dev Caller must have the MINTER_ROLE
     * @param to Account to receive the new shares
     * @param amount Amount of shares to mint
     */
    function mintShares(address to, uint256 amount) external;

    /**
     * @notice Destroy a `value` amount of tokens from the caller, reducing the total supply
     * @param value Amount of tokens to burn, is internally converted to the proper shares amounts
     */
    function burn(uint256 value) external;

    /**
     * @notice Destroy a `value` amount of tokens from `account`, deducting from the caller's allowance
     * @param account Account to burn tokens from
     * @param value Amount of tokens to burn, is internally converted to the proper shares amounts
     */
    function burnFrom(address account, uint256 value) external;

    /**
     * @notice Destroy a `value` amount of shares from the caller, reducing the total supply
     * @param value Amount of shares to burn
     */
    function burnShares(uint256 value) external;

    /**
     * @notice Destroy a `value` amount of shares from `account`, deducting from the caller's allowance
     * @param account Account to burn shares from
     * @param value Amount of shares to burn
     */
    function burnSharesFrom(address account, uint256 value) external;

    /**
     * @notice Convert a number of tokens to the corresponding amount of shares
     * @dev The conversion reverts with `UsdnMaxTokensExceeded` if the corresponding amount of shares overflows
     * @param amountTokens The amount of tokens to convert to shares
     * @return shares_ The corresponding amount of shares
     */
    function convertToShares(uint256 amountTokens) external view returns (uint256 shares_);

    /**
     * @notice Convert a number of shares to the corresponding amount of tokens
     * @dev The conversion never overflows as we are performing a division. The conversion rounds to the nearest amount
     * of tokens that minimizes the error when converting back to shares
     * @param amountShares The amount of shares to convert to tokens
     * @return tokens_ The corresponding amount of tokens
     */
    function convertToTokens(uint256 amountShares) external view returns (uint256 tokens_);

    /**
     * @notice View function returning the current maximum tokens supply, given the current divisor
     * @dev This function is used to check if a conversion operation would overflow
     * @return maxTokens_ The maximum number of tokens that can exist
     */
    function maxTokens() external view returns (uint256 maxTokens_);

    /**
     * @notice Restricted function to decrease the global divisor, which effectively grows all balances and the total
     * supply
     * @param divisor The new divisor, must be strictly smaller than the current one and greater or equal to
     * MIN_DIVISOR
     */
    function rebase(uint256 divisor) external;

    /* -------------------------------------------------------------------------- */
    /*                             Dev view functions                             */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice The current value of the divisor that converts between tokens and shares
     * @return The current divisor
     */
    function divisor() external view returns (uint256);

    /**
     * @notice Minter role signature
     * @return The role signature
     */
    function MINTER_ROLE() external pure returns (bytes32);

    /**
     * @notice Rebaser role signature
     * @return The role signature
     */
    function REBASER_ROLE() external pure returns (bytes32);

    /**
     * @notice Maximum value of the divisor, which is also the initial value
     * @return The maximum divisor
     */
    function MAX_DIVISOR() external pure returns (uint256);

    /**
     * @notice Minimum acceptable value of the divisor
     * @dev The minimum divisor that can be set. This corresponds to a growth of 1B times. Technically, 1e5 would still
     * work without precision errors
     * @return The minimum divisor
     */
    function MIN_DIVISOR() external pure returns (uint256);
}

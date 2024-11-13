// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { IERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";

import { IRebaseCallback } from "./IRebaseCallback.sol";
import { IUsdnErrors } from "./IUsdnErrors.sol";
import { IUsdnEvents } from "./IUsdnEvents.sol";

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
     * @dev There should be sufficient allowance for the spender. Be careful to the rebase logic. The allowance is in
     * tokens. So, after a rebasing, the same amount of shares will be worth a higher amount of tokens. In this case,
     * the allowance of the initial tokens will not be enough to transfer the new amount of tokens. This workflow can be
     * also happen when your transaction is in a mempool and the rebase pass before your transaction
     * @param from The owner of the shares
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
     * @return mintedTokens_ Amount of tokens that were minted (informational)
     */
    function mintShares(address to, uint256 amount) external returns (uint256 mintedTokens_);

    /**
     * @notice Destroy a `value` amount of tokens from the caller, reducing the total supply
     * @param value Amount of tokens to burn, is internally converted to the proper shares amounts
     */
    function burn(uint256 value) external;

    /**
     * @notice Destroy a `value` amount of tokens from `account`, deducting from the caller's allowance
     * @dev There should be sufficient allowance for the spender. Be careful to the rebase logic. The allowance is in
     * tokens. So, after a rebasing, the same amount of shares will be worth a higher amount of tokens. In this case,
     * the allowance of the initial tokens will not be enough to burn the new amount of tokens. This workflow can be
     * also happen when your transaction is in a mempool and the rebase pass before your transaction
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
     * @notice Convert a number of shares to the corresponding amount of tokens, rounding up
     * @dev Use this function to determine the amount of a token approval, as we always round up when deducting from
     * a token transfer allowance
     * @param amountShares The amount of shares to convert to tokens
     * @return tokens_ The corresponding amount of tokens, rounded up
     */
    function convertToTokensRoundUp(uint256 amountShares) external view returns (uint256 tokens_);

    /**
     * @notice View function returning the current maximum tokens supply, given the current divisor
     * @dev This function is used to check if a conversion operation would overflow
     * @return maxTokens_ The maximum number of tokens that can exist
     */
    function maxTokens() external view returns (uint256 maxTokens_);

    /**
     * @notice Restricted function to decrease the global divisor, which effectively grows all balances and the total
     * supply
     * @dev If the provided divisor is larger than or equal to the current divisor value, no rebase will happen
     * If the new divisor is smaller than `MIN_DIVISOR`, the value will be clamped to `MIN_DIVISOR`
     * Caller must have the `REBASER_ROLE`
     * @param divisor The new divisor, should be strictly smaller than the current one and greater or equal to
     * `MIN_DIVISOR`
     * @return rebased_ Whether a rebase happened
     * @return oldDivisor_ The previous value of the divisor
     * @return callbackResult_ The result of the callback, if a rebase happened and a callback handler is defined
     */
    function rebase(uint256 divisor)
        external
        returns (bool rebased_, uint256 oldDivisor_, bytes memory callbackResult_);

    /**
     * @notice Restricted function to set the address of the rebase handler
     * @dev Emits a `RebaseHandlerUpdated` event
     * If set to the zero address, no handler will be called after a rebase
     * Caller must have the `DEFAULT_ADMIN_ROLE`
     * @param newHandler The new handler address
     */
    function setRebaseHandler(IRebaseCallback newHandler) external;

    /* -------------------------------------------------------------------------- */
    /*                             Dev view functions                             */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice The current value of the divisor that converts between tokens and shares
     * @return The current divisor
     */
    function divisor() external view returns (uint256);

    /**
     * @notice The address of the rebase handler, which is called whenever a rebase happens
     * @return The rebase handler address
     */
    function rebaseHandler() external view returns (IRebaseCallback);

    /**
     * @notice The minter role signature
     * @return The role signature
     */
    function MINTER_ROLE() external pure returns (bytes32);

    /**
     * @notice The rebaser role signature
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

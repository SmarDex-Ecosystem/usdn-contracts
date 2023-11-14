// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title Events for the USDN token contract
 * @author @beeb
 */
interface IUsdnEvents {
    /**
     * @notice Emitted when the multiplier is adjusted.
     * @param old_multiplier multiplier before adjustment
     * @param new_multiplier multiplier after adjustment
     */
    event MultiplierAdjusted(uint256 old_multiplier, uint256 new_multiplier);
}

/**
 * @title Errors for the USDN token contract
 * @author @beeb
 */
interface IUsdnErrors {
    /**
     * @dev Indicates that the provided multiplier is invalid. This is usually because the new value is smaller or
     * equal to the current multiplier.
     * @param multiplier invalid multiplier
     */
    error InvalidMultiplier(uint256 multiplier);

    /// @dev Permit deadline has expired.
    error ERC2612ExpiredSignature(uint256 deadline);

    /// @dev Mismatched signature.
    error ERC2612InvalidSigner(address signer, address owner);
}

/**
 * @title USDN token interface
 * @author @beeb
 * @notice Implements the ERC-20 token standard as well as the EIP-2612 permit extension. Additional functions related
 * to the specifics of this token are also included.
 */
interface IUsdn {
    /**
     * @notice Return the token decimals.
     * @return decimals the number of decimals of the ERC-20 token.
     */
    function decimals() external pure returns (uint8 decimals);

    /**
     * @notice Name of the token.
     * @return name the name string
     */
    function name() external pure returns (string memory name);

    /**
     * @notice Symbol of the token.
     * @return symbol the symbol string
     */
    function symbol() external pure returns (string memory symbol);

    /**
     * @notice Total supply of the token.
     * @return totalSupply the total supply
     */
    function totalSupply() external view returns (uint256 totalSupply);

    /**
     * @notice Balance of the token for a given account.
     * @param account the account to query
     * @return balance the balance
     */
    function balanceOf(address account) external view returns (uint256 balance);

    /**
     * @notice Get the remaining number of tokens that `spender` will be allowed to spend on behalf of `owner` through
     * `transferFrom`. This is zero by default.
     * @param owner the account that owns the tokens
     * @param spender the account that will spend the tokens
     * @return allowance the remaining allowance
     */
    function allowance(address owner, address spender) external view returns (uint256 allowance);

    /**
     * @notice Return the current nonce for `owner`. This value must be included whenever a signature is generated for
     * {permit}.
     *
     * Every successful call to {permit} increases the nonce of `owner` by one. This prevents a signature from being
     * used multiple times.
     * @param owner the account to query
     * @return nonce the current nonce for `owner`
     */
    function nonces(address owner) external view returns (uint256 nonce);

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
     * @notice Set `value` as the allowance of `spender` over the caller's tokens.
     * @dev IMPORTANT: Beware that changing an allowance with this method brings the risk that someone may use both the
     * old and the new allowance by unfortunate transaction ordering. One possible solution to mitigate this race
     * condition is to first reduce the spender's allowance to 0 and set the desired value afterwards:
     * https://github.com/ethereum/EIPs/issues/20#issuecomment-263524729
     *
     * Emits an {Approval} event.
     * @param spender the account that will spend the tokens
     * @param value the amount of tokens to allow, is internally converted to shares
     * @return success true if the operation succeeded
     */
    function approve(address spender, uint256 value) external returns (bool success);

    /**
     * @notice Move a `value` amount of tokens from the caller to `to`.
     * @dev Emits a {Transfer} event.
     * @param to the destination address
     * @param value the amount of tokens to send, is internally converted to shares
     * @return success true if the operation succeeded
     */
    function transfer(address to, uint256 value) external returns (bool success);

    /**
     * @notice Move a `value` amount of tokens from `from` to `to` using the allowance mechanism. `value` is then
     * deducted from the caller's allowance.
     * @dev Emits a {Transfer} event.
     * @param from the source address
     * @param to the destination address
     * @param value the amount of tokens to send, is internally converted to shares
     * @return success true if the operation succeeded
     */
    function transferFrom(address from, address to, uint256 value) external returns (bool success);

    /**
     * @notice Set `value` as the allowance of `spender` over `owner`'s tokens, given `owner`'s signed approval.
     * @dev IMPORTANT: See {approve} for concerns about transaction ordering.
     *
     * Requirements:
     *  - `spender` cannot be the zero address.
     *  - `deadline` must be a timestamp in the future.
     *  - `v`, `r` and `s` must be a valid `secp256k1` signature from `owner` over the EIP712-formatted function args.
     *  - the signature must use `owner`'s current nonce (see {nonces})
     *
     * Emits an {Approval} event.
     * @param owner the account that owns the tokens
     * @param spender the account that will spend the tokens
     * @param value the amount of tokens to allow
     * @param deadline the deadline timestamp, type(uint256).max for no deadline
     * @param v v of the signature
     * @param r r of the signature
     * @param s s of the signature
     */
    function permit(address owner, address spender, uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s)
        external;

    /**
     * @notice Destroy a `value` amount of tokens from the caller, lowering the total supply.
     * @dev Emits a {Transfer} event with the zero address as `to`.
     * @param value the amount of tokens to burn, is internally converted to shares
     */
    function burn(uint256 value) external;

    /**
     * @notice Destroy a `value` amount of tokens from `account`, deducting from the caller's allowance, lowering the
     * total supply.
     * @param account the account to burn the tokens from
     * @param value the amount of tokens to burn, is internally converted to shares
     */
    function burnFrom(address account, uint256 value) external;

    /**
     * @notice Restricted function to mint new shares, providing a token value.
     * @dev Caller must have the MINTER_ROLE.
     * @param to account to receive the new shares
     * @param amount amount of tokens to mint, is internally converted to the proper shares amounts
     */
    function mint(address to, uint256 amount) external;

    /**
     * @notice Restricted function to increase the global multiplier, which effectively grows all balances and the total
     * supply.
     * @param multiplier the new multiplier, must be greater than the current one
     */
    function adjustMultiplier(uint256 multiplier) external;

    /**
     * @dev The domain separator used in the encoding of the signature for {permit}, as defined by EIP-712.
     * @return domainSeparator the domain separator
     */
    function DOMAIN_SEPARATOR() external view returns (bytes32 domainSeparator);

    /// @dev Minter role signature.
    function MINTER_ROLE() external view returns (bytes32);

    /// @dev Adjustment role signature.
    function ADJUSTMENT_ROLE() external view returns (bytes32);
}

// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { IERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";

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
    error UsdnInvalidMultiplier(uint256 multiplier);

    /// @dev Permit deadline has expired.
    error ERC2612ExpiredSignature(uint256 deadline);

    /// @dev Mismatched signature.
    error ERC2612InvalidSigner(address signer, address owner);
}

/**
 * @title USDN token interface
 * @author @beeb
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

    /// @dev Minter role signature.
    function MINTER_ROLE() external pure returns (bytes32);

    /// @dev Adjustment role signature.
    function ADJUSTMENT_ROLE() external pure returns (bytes32);

    /// @dev The additional precision for shares compared to tokens.
    function decimalsOffset() external pure returns (uint8);
}

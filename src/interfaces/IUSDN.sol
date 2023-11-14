// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IUSDNEvents {
    /**
     * @notice Emitted when the multiplier is adjusted.
     * @param old_multiplier multiplier before adjustment
     * @param new_multiplier multiplier after adjustment
     */
    event MultiplierAdjusted(uint256 old_multiplier, uint256 new_multiplier);
}

interface IUSDNErrors {
    /**
     * @dev Indicates that the provided multiplier is invalid. This is usually because the new value is smaller or
     * equal to the current multiplier.
     * @param multiplier invalid multiplier
     */
    error InvalidMultiplier(uint256 multiplier);

    /**
     * @dev Permit deadline has expired.
     */
    error ERC2612ExpiredSignature(uint256 deadline);

    /**
     * @dev Mismatched signature.
     */
    error ERC2612InvalidSigner(address signer, address owner);
}

/**
 * @dev Interface for the functions of the USDN token which are not part of the ERC-20 standard.
 */
interface IUSDN {
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
     * @notice Restricted function to increase the global multiplier, which effectively grows all balances and the total
     * supply.
     * @param multiplier the new multiplier, must be greater than the current one
     */
    function adjustMultiplier(uint256 multiplier) external;

    /**
     * @dev Minter role signature.
     */
    function MINTER_ROLE() external view returns (bytes32);

    /**
     * @dev Adjustment role signature.
     */
    function ADJUSTMENT_ROLE() external view returns (bytes32);
}

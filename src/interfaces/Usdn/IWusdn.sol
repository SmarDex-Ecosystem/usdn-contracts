// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import { IERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";

import { IWusdnEvents } from "./IWusdnEvents.sol";
import { IWusdnErrors } from "./IWusdnErrors.sol";
import { IUsdn } from "./IUsdn.sol";

/**
 * @title Wusdn Interface
 * @notice Interface for the Wrapped Ultimate Synthetic Delta Neutral (WUSDN) token
 */
interface IWusdn is IERC20Permit, IWusdnEvents, IWusdnErrors {
    /**
     * @notice Returns the USDN token address
     * @return The address of the USDN token
     */
    function USDN() external view returns (IUsdn);

    /**
     * @notice The ratio used to convert USDN shares to WUSDN amounts
     * @dev It is initialized in the constructor at the maximum divisor of the USDN token
     * @return The ratio used between USDN shares and WUSDN amounts
     */
    function SHARES_RATIO() external view returns (uint256);

    /**
     * @notice Wraps USDN into WUSDN
     * @dev This function can use less than `usdnAmount` to account for rounding errors
     * For a more precise amount, use {wrapShares}
     * @param usdnAmount The amount of USDN to wrap
     * @return wrappedAmount_ The amount of WUSDN received
     */
    function wrap(uint256 usdnAmount) external returns (uint256 wrappedAmount_);

    /**
     * @notice Wraps USDN into WUSDN to a specified address
     * @dev This function can use less than `usdnAmount` to account for rounding errors
     * For a more precise amount, use {wrapShares}
     * @param usdnAmount The amount of USDN to wrap
     * @param to The address to receive the WUSDN
     * @return wrappedAmount_ The amount of WUSDN received
     */
    function wrap(uint256 usdnAmount, address to) external returns (uint256 wrappedAmount_);

    /**
     * @notice Wraps USDN shares into WUSDN to a specified address
     * @param usdnShares The amount of USDN shares to wrap
     * @param to The address to receive the WUSDN
     * @return wrappedAmount_ The amount of WUSDN received
     */
    function wrapShares(uint256 usdnShares, address to) external returns (uint256 wrappedAmount_);

    /**
     * @notice Unwraps WUSDN into USDN
     * @param wusdnAmount The amount of WUSDN to unwrap
     * @return usdnAmount_ The amount of USDN received
     */
    function unwrap(uint256 wusdnAmount) external returns (uint256 usdnAmount_);

    /**
     * @notice Unwraps WUSDN into USDN to a specified address
     * @param wusdnAmount The amount of WUSDN to unwrap
     * @param to The address to receive the USDN
     * @return usdnAmount_ The amount of USDN received
     */
    function unwrap(uint256 wusdnAmount, address to) external returns (uint256 usdnAmount_);

    /**
     * @notice Previews the amount of WUSDN that would be received for a given amount of USDN
     * @dev This function can return a slightly different value (1wei) from the actual amount
     * received due to rounding errors
     * Do not rely on this function to calculate the exact amount of WUSDN that would be received, use
     * {previewWrapShares} instead
     * @param usdnAmount The amount of USDN to preview
     * @return wrappedAmount_ The amount of WUSDN that would be received
     */
    function previewWrap(uint256 usdnAmount) external view returns (uint256 wrappedAmount_);

    /**
     * @notice Previews the amount of WUSDN that would be received for a given amount of USDN shares
     * @param usdnShares The amount of USDN shares to preview
     * @return wrappedAmount_ The amount of WUSDN that would be received
     */
    function previewWrapShares(uint256 usdnShares) external view returns (uint256 wrappedAmount_);

    /**
     * @notice Previews the amount of USDN that would be received for a given amount of WUSDN
     * @param wusdnAmount The amount of WUSDN to preview
     * @return usdnAmount_ The amount of USDN that would be received
     */
    function previewUnwrap(uint256 wusdnAmount) external view returns (uint256 usdnAmount_);

    /**
     * @notice Returns the total amount of USDN held by the contract
     * @return The total amount of USDN held by the contract
     */
    function totalUsdnBalance() external view returns (uint256);

    /**
     * @notice Returns the total amount of USDN shares held by the contract
     * @return The total amount of USDN shares held by the contract
     */
    function totalUsdnShares() external view returns (uint256);
}

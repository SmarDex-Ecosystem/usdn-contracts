// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { IERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";

import { IUsdn } from "./IUsdn.sol";
import { IWusdnErrors } from "./IWusdnErrors.sol";
import { IWusdnEvents } from "./IWusdnEvents.sol";

/**
 * @title IWusdn Interface
 * @notice Interface for the Wrapped Ultimate Synthetic Delta Neutral (WUSDN) token.
 */
interface IWusdn is IERC20Metadata, IERC20Permit, IWusdnEvents, IWusdnErrors {
    /**
     * @notice Returns the address of the USDN token.
     * @return The address of the USDN token.
     */
    function USDN() external view returns (IUsdn);

    /**
     * @notice Returns the ratio used to convert USDN shares to WUSDN amounts.
     * @dev This ratio is initialized in the constructor based on the maximum divisor of the USDN token.
     * @return The conversion ratio between USDN shares and WUSDN amounts.
     */
    function SHARES_RATIO() external view returns (uint256);

    /**
     * @notice Wraps a given amount of USDN into WUSDN.
     * @dev This function may use slightly less than `usdnAmount` to account for rounding errors.
     * For a more precise operation, use {wrapShares}.
     * @param usdnAmount The amount of USDN to wrap.
     * @return wrappedAmount_ The amount of WUSDN received.
     */
    function wrap(uint256 usdnAmount) external returns (uint256 wrappedAmount_);

    /**
     * @notice Wraps a specified amount of USDN into WUSDN and sends it to a specified address.
     * @dev This function may use slightly less than `usdnAmount` to account for rounding errors.
     * For a more precise operation, use {wrapShares}.
     * @param usdnAmount The amount of USDN to wrap.
     * @param to The address to receive the WUSDN.
     * @return wrappedAmount_ The amount of WUSDN received.
     */
    function wrap(uint256 usdnAmount, address to) external returns (uint256 wrappedAmount_);

    /**
     * @notice Wraps a given amount of USDN shares into WUSDN and sends it to a specified address.
     * @param usdnShares The amount of USDN shares to wrap.
     * @param to The address to receive the WUSDN.
     * @return wrappedAmount_ The amount of WUSDN received.
     */
    function wrapShares(uint256 usdnShares, address to) external returns (uint256 wrappedAmount_);

    /**
     * @notice Unwraps a given amount of WUSDN into USDN.
     * @param wusdnAmount The amount of WUSDN to unwrap.
     * @return usdnAmount_ The amount of USDN received.
     */
    function unwrap(uint256 wusdnAmount) external returns (uint256 usdnAmount_);

    /**
     * @notice Unwraps a given amount of WUSDN into USDN and sends it to a specified address.
     * @param wusdnAmount The amount of WUSDN to unwrap.
     * @param to The address to receive the USDN.
     * @return usdnAmount_ The amount of USDN received.
     */
    function unwrap(uint256 wusdnAmount, address to) external returns (uint256 usdnAmount_);

    /**
     * @notice Previews the amount of WUSDN that would be received for a given amount of USDN.
     * @dev The actual amount received may differ slightly due to rounding errors.
     * For a precise value, use {previewWrapShares}.
     * @param usdnAmount The amount of USDN to wrap.
     * @return wrappedAmount_ The estimated amount of WUSDN that would be received.
     */
    function previewWrap(uint256 usdnAmount) external view returns (uint256 wrappedAmount_);

    /**
     * @notice Previews the amount of WUSDN that would be received for a given amount of USDN shares.
     * @param usdnShares The amount of USDN shares to wrap.
     * @return wrappedAmount_ The amount of WUSDN that would be received.
     */
    function previewWrapShares(uint256 usdnShares) external view returns (uint256 wrappedAmount_);

    /**
     * @notice Previews the amount of USDN that would be received for a given amount of WUSDN.
     * @dev The actual amount received may differ slightly due to rounding errors.
     * For a precise value, use {previewUnwrapShares}.
     * @param wusdnAmount The amount of WUSDN to unwrap.
     * @return usdnAmount_ The estimated amount of USDN that would be received.
     */
    function previewUnwrap(uint256 wusdnAmount) external view returns (uint256 usdnAmount_);

    /**
     * @notice Previews the amount of USDN shares that would be received for a given amount of WUSDN.
     * @param wusdnAmount The amount of WUSDN to unwrap.
     * @return usdnSharesAmount_ The amount of USDN shares that would be received.
     */
    function previewUnwrapShares(uint256 wusdnAmount) external view returns (uint256 usdnSharesAmount_);

    /**
     * @notice Returns the total amount of USDN held by the contract.
     * @return The total amount of USDN held by the contract.
     */
    function totalUsdnBalance() external view returns (uint256);

    /**
     * @notice Returns the total amount of USDN shares held by the contract.
     * @return The total amount of USDN shares held by the contract.
     */
    function totalUsdnShares() external view returns (uint256);
}

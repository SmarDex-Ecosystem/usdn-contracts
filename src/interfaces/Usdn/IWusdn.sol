// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import { IERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";

import { IWusdnEvents } from "src/interfaces/Usdn/IWusdnEvents.sol";
import { IUsdn } from "src/interfaces/Usdn/IUsdn.sol";

/**
 * @title Wusdn Interface
 * @notice Interface for the Wrapped Ultimate Synthetic Delta Neutral (WUSDN) token
 */
interface IWusdn is IERC20Permit, IWusdnEvents {
    /**
     * @notice Returns the USDN token address
     * @return The address of the USDN token
     */
    function USDN() external view returns (IUsdn);

    /**
     * @notice Wraps USDN into WUSDN
     * @param usdnAmount The amount of USDN to wrap
     * @return wrappedAmount_ The amount of WUSDN received
     */
    function wrap(uint256 usdnAmount) external returns (uint256 wrappedAmount_);

    /**
     * @notice Wraps USDN into WUSDN to a specified address
     * @param usdnAmount The amount of USDN to wrap
     * @param to The address to receive the WUSDN
     * @return wrappedAmount_ The amount of WUSDN received
     */
    function wrap(uint256 usdnAmount, address to) external returns (uint256 wrappedAmount_);

    /**
     * @notice Wraps USDN from a specified address into WUSDN to another address
     * @param from The address to wrap the USDN from
     * @param usdnAmount The amount of USDN to wrap
     * @param to The address to receive the WUSDN
     * @return wrappedAmount_ The amount of WUSDN received
     */
    function wrapFrom(address from, uint256 usdnAmount, address to) external returns (uint256 wrappedAmount_);

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
     * @notice Unwraps WUSDN from a specified address into USDN to another address
     * @param from The address to unwrap the WUSDN from
     * @param wusdnAmount The amount of WUSDN to unwrap
     * @param to The address to receive the USDN
     * @return usdnAmount_ The amount of USDN received
     */
    function unwrapFrom(address from, uint256 wusdnAmount, address to) external returns (uint256 usdnAmount_);

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
    function totalUsdn() external view returns (uint256);

    /**
     * @notice Previews the amount of WUSDN that would be received for a given amount of USDN
     * @param usdnAmount The amount of USDN to preview
     * @return wrappedAmount_ The amount of WUSDN that would be received
     */
    function previewWrap(uint256 usdnAmount) external view returns (uint256 wrappedAmount_);
}

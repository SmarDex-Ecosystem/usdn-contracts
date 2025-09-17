// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { IUsdn } from "./IUsdn.sol";

/**
 * @title USDNr Token Interface
 * @notice The USDNr token is a wrapper around the USDN token, allowing users to wrap and unwrap USDN at a 1:1 ratio.
 */
interface IUsdnr is IERC20Metadata {
    /// @notice The amount provided is zero.
    error USDNrZeroAmount();

    /**
     * @notice Wraps USDN into USDNr at a 1:1 ratio.
     * @param usdnAmount The amount of USDN to wrap.
     */
    function wrap(uint256 usdnAmount) external;

    /**
     * @notice Unwraps USDNr into USDN at a 1:1 ratio.
     * @param usdnrAmount The amount of USDNr to unwrap.
     */
    function unwrap(uint256 usdnrAmount) external;

    /**
     * @notice Returns the address of the USDN token contract.
     * @return usdn_ The address of the USDN token contract.
     */
    function USDN() external view returns (IUsdn usdn_);

    /**
     * @notice Returns the total amount of USDN that has been wrapped into USDNr.
     * @return totalWrapped_ The total amount of USDN wrapped into USDNr.
     */
    function getTotalWrapped() external view returns (uint256 totalWrapped_);
}

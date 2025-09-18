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

    /// @notice The recipient address is the zero address.
    error USDNrZeroRecipient();

    /**
     * @notice Wraps USDN into USDNr at a 1:1 ratio.
     *  @dev When approving USDN, use the `convertToTokensRoundUp` of the user shares, as we always round up when
     * deducting from a token transfer allowance.
     * @param usdnAmount The amount of USDN to wrap.
     * @param recipient The address to receive the USDNr tokens.
     */
    function wrap(uint256 usdnAmount, address recipient) external;

    /**
     * @notice Unwraps USDNr into USDN at a 1:1 ratio.
     * @param usdnrAmount The amount of USDNr to unwrap.
     * @param recipient The address to receive the USDN tokens.
     */
    function unwrap(uint256 usdnrAmount, address recipient) external;

    /**
     * @notice Returns the address of the USDN token contract.
     * @return usdn_ The address of the USDN token contract.
     */
    function USDN() external view returns (IUsdn usdn_);
}

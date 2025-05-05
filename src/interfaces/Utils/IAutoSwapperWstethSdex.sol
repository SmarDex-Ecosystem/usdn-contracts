// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.0;

/**
 * @title IAutoSwapperWstethSdex
 * @notice Interface for the AutoSwapperWstethSdex contract that provides automated token swapping functionality.
 */
interface IAutoSwapperWstethSdex {
    /**
     * @notice Swap wstETH to SDEX.
     * @dev This function can only be called by the contract itself.
     */
    function swapWstethToSdex() external;

    /**
     * @notice Admin function to send the contract token balance to a specified address.
     * @param token The address of the token to send.
     * @param to The recipient address.
     * @param amount The amount of tokens to send.
     */
    function sweep(address token, address to, uint256 amount) external;

    /// @notice Initiates a swap from wstETH to SDEX.
    function forceSwap() external;

    /**
     * @notice Updates the allowed slippage percentage for swaps.
     * @param swapSlippage The new slippage value (in basis points).
     */
    function updateSwapSlippage(uint256 swapSlippage) external;

    /* -------------------------------------------------------------------------- */
    /*                                   Events                                   */
    /* -------------------------------------------------------------------------- */

    /// @notice Emitted when a swap fails.
    event FailedSwap();

    /**
     * @notice Emitted when the swap slippage percentage is updated.
     * @param newSwapSlippage The new swap slippage (in basis points).
     */
    event SwapSlippageUpdated(uint256 newSwapSlippage);

    /* -------------------------------------------------------------------------- */
    /*                                   Errors                                   */
    /* -------------------------------------------------------------------------- */

    /// @notice Thrown when a swap fails.
    error AutoSwapperSwapFailed();

    /// @notice Thrown when slippage configuration is invalid.
    error AutoSwapperInvalidSwapSlippage();

    /// @notice Thrown when the caller is not authorized to perform the operation.
    error AutoSwapperInvalidCaller();
}

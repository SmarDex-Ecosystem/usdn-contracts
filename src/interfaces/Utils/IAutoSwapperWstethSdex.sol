// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.0;

/**
 * @title IAutoSwapperWstethSdex
 * @notice Interface for the AutoSwapperWstethSdex contract that provides automated token swapping functionality.
 */
interface IAutoSwapperWstethSdex {
    /// @notice Swaps wstETH for WETH on Uniswap V3.
    function uniWstethToWeth() external;

    /**
     * @notice Callback function for Uniswap V3 swaps.
     * @param amount0Delta The amount of token0 swapped.
     * @param amount1Delta The amount of token1 swapped.
     * @param data Additional data passed to the callback.
     */
    function uniswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata data) external;

    /// @notice Swaps WETH for SDEX token using the SmarDex protocol.
    function smarDexWethToSdex() external;

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
     * @param swapSlippage The new slippage value (in BPS).
     */
    function updateSwapSlippage(uint256 swapSlippage) external;

    /* -------------------------------------------------------------------------- */
    /*                                   Events                                   */
    /* -------------------------------------------------------------------------- */

    /// @notice Emitted when the swap from wstETH to WETH fails.
    event FailedWstEthSwap();

    /// @notice Emitted when the swap from WETH to SDEX fails.
    event FailedWEthSwap();

    /**
     * @notice Emitted when the swap slippage percentage is updated.
     * @param newSwapSlippage The new swap slippage (in BPS).
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

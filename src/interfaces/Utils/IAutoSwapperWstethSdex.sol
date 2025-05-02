// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.0;

/**
 * @title IAutoSwapperWstethSdex
 * @notice Interface for the AutoSwapperWstethSdex contract that provides automated token swapping functionality.
 * @dev Handles token swaps via SmarDex and Uniswap V3 with price protection mechanisms.
 */
interface IAutoSwapperWstethSdex {
    /**
     * @notice Swaps wstETH for WETH on Uniswap V3.
     * @param wstethAmount The amount of wstETH to swap.
     */
    function uniWstethToWeth(uint256 wstethAmount) external;

    /**
     * @notice Callback function for Uniswap V3 swaps.
     * @param amount0Delta The amount of token0 swapped.
     * @param amount1Delta The amount of token1 swapped.
     * @param data Additional data passed to the callback.
     */
    function uniswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata data) external;

    /**
     * @notice Swaps WETH for SDEX token using the SmarDex protocol.
     * @param wethAmount The amount of WETH to swap.
     */
    function smarDexWethToSdex(uint256 wethAmount) external;

    /**
     * @notice Callback function for SmarDex swaps.
     * @param amount0Delta The amount of token0 swapped.
     * @param amount1Delta The amount of token1 swapped.
     * @param data Additional data passed to the callback.
     */
    function smardexSwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata data) external;

    /**
     * @notice Admin function to send tokens to a specified address.
     * @param token The address of the token to send.
     * @param to The address to send the tokens.
     * @param amount The amount of tokens to send.
     * @dev Can only be called by the contract owner.
     */
    function sweep(address token, address to, uint256 amount) external;

    /**
     * @notice Updates the allowed slippage percentage for swaps.
     * @param swapSlippage The new slippage value (in percent, e.g., 2 for 2%).
     * @dev Reverts if the provided slippage is zero.
     */
    function updateSwapSlippage(uint256 swapSlippage) external;

    /* -------------------------------------------------------------------------- */
    /*                                   Events                                   */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice Emitted when the swap from wstETH to SDEX completes successfully.
     * @param wstEthAmount The amount of wstETH that was swapped.
     */
    event SuccessfulSwap(uint256 wstEthAmount);

    /// @notice Emitted when the swap from wstETH to WETH fails.
    event FailedWstEthSwap();

    /// @notice Emitted when the swap from WETH to SDEX fails.
    event FailedWEthSwap();

    /**
     * @notice Emitted when the swap slippage percentage is updated.
     * @param newSwapSlippage The new swap slippage percentage.
     */
    event SwapSlippageUpdated(uint256 newSwapSlippage);

    /* -------------------------------------------------------------------------- */
    /*                                   Errors                                   */
    /* -------------------------------------------------------------------------- */

    /// @notice Thrown when a swap is attempted with zero amount.
    error AutoSwapperInvalidAmount();

    /// @notice Thrown when a swap fails.
    error AutoSwapperSwapFailed();

    /// @notice Thrown when slippage configuration is invalid.
    error AutoSwapperInvalidSwapSlippage();

    /// @notice Thrown when the caller is not authorized to perform the operation.
    error AutoSwapperInvalidCaller();
}

// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

interface IAutoSwapper {
    /**
     * @notice Executes a two-step swap: wstETH → WETH → SDEX.
     * @dev If the first swap fails, the second is skipped.
     * If the second swap fails, it is silently ignored.
     * @param _amount Amount of wstETH to process.
     */
    function processSwap(uint256 _amount) external;

    /**
     * @notice onlyOwner function to swap token in SDEX.
     * @param _amountToSwap amount of tokens from _path[0] to be converted into SDEX
     * @param _amountOutMin The minimum SDEX amount required to prevent the transaction from reverting
     * @param _path An array of token addresses.
     * @param _command instruction for router to excecute.
     */
    function swapTokenWithPath(uint256 _amountToSwap, uint256 _amountOutMin, address[] calldata _path, uint8 _command)
        external;

    /**
     * @notice Swaps wstETH to WETH via Uniswap V3.
     * @param amount Amount of wstETH to swap.
     */
    function safeSwapV3(uint256 amount) external;

    /**
     * @notice Swaps WETH to SDEX via the Universal Router.
     */
    function safeSwapSmarDex() external;

    /**
     * @notice Updates the Uniswap V3 fee tier used when constructing the swap path.
     * @param _feeTier The new fee tier (in hundredths of a bip, e.g. 500 = 0.05%).
     */
    function updateUniswapFeeTier(uint24 _feeTier) external;

    /**
     * @notice Updates the address of the Uniswap pool used for TWAP calculations.
     * @param _newPair The new Uniswap pool address. Must not be the zero address.
     */
    function updateUniswapPair(address _newPair) external;

    /**
     * @notice Updates the TWAP interval used for price calculations.
     * @param _newTwapInterval The new interval in seconds. Must be greater than zero.
     */
    function updateTwapInterval(uint32 _newTwapInterval) external;

    /**
     * @notice Updates the allowed slippage percentage for swaps.
     * @param _swapSlippage The new slippage value (in percent, e.g., 2 for 2%).
     * @dev Reverts if the provided slippage is zero.
     */
    function updateSwapSlippage(uint256 _swapSlippage) external;

    /* -------------------------------------------------------------------------- */
    /*                                   Events                                   */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice Emitted when the swap from wstETH to SDEX completes successfully
     * @param wstEthAmount The amount of wstETH that was swapped
     */
    event sucessfullSwap(uint256 wstEthAmount);

    /**
     * @notice Emitted when the swap from wstETH to WETH fails
     * @param wstEthAmount The amount of wstETH attempted to be swapped
     */
    event failedWstEthSwap(uint256 wstEthAmount);

    /**
     * @notice Emitted when the swap from WETH to SDEX fails
     * @param wEthAmount The amount of WETH attempted to be swapped
     */
    event failedWEthSwap(uint256 wEthAmount);

    /* -------------------------------------------------------------------------- */
    /*                                   Errors                                   */
    /* -------------------------------------------------------------------------- */
    /// @notice Thrown when the wstETH address provided is invalid (zero address).
    error InvalidWstETHAddress();

    /// @notice Thrown when the WETH address provided is invalid (zero address).
    error InvalidWETHAddress();

    /// @notice Thrown when the SDEX token address provided is invalid (zero address).
    error InvalidSDEXAddress();

    /// @notice Thrown when the router address provided is invalid (zero address).
    error InvalidRouterAddress();

    /// @notice Thrown when an empty swap path is provided.
    error InvalidPath();

    /// @notice Thrown when the last token in the path is not SDEX.
    error InvalidLastToken();

    /// @notice Thrown when a swap is attempted with zero amount.
    error InvalidAmount();

    /// @notice Thrown when the TWAP interval is set to zero.
    error InvalidTwapInterval();

    /// @notice Thrown when an invalid Uniswap pair address is set.
    error InvalidPairAddress();

    /// @notice Thrown when the Uniswap fee tier is invalid
    error InvalidUniswapFee();

    /// @notice Thrown when slippage configuration is invalid.
    error InvalidSwapSlippage();
}

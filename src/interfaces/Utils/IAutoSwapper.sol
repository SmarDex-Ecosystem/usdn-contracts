// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import { ISmardexPair } from "@smardex-dex-contracts/contracts/ethereum/core/v2/interfaces/ISmardexPair.sol";

interface IAutoSwapper {
    /**
     * @notice swap parameters used by function _swapAndSend
     * @param zeroForOne true if we swap the token0 with token1, false otherwise
     * @param balanceIn balance of in-token to be swapped
     * @param pair pair address
     * @param fictiveReserve0 fictive reserve of token0 of the pair
     * @param fictiveReserve1 fictive reserve of token1 of the pair
     * @param oldPriceAv0 priceAverage of token0 of the pair before the swap
     * @param oldPriceAv1 priceAverage of token1 of the pair before the swap
     * @param oldPriceAvTimestamp priceAverageLastTimestamp of the pair before the swap
     * @param newPriceAvIn priceAverage of token0 of the pair after the swap
     * @param newPriceAvOut priceAverage of token1 of the pair after the swap
     */
    struct SwapCallParams {
        bool zeroForOne;
        uint256 balanceIn;
        ISmardexPair pair;
        uint256 fictiveReserve0;
        uint256 fictiveReserve1;
        uint256 oldPriceAv0;
        uint256 oldPriceAv1;
        uint256 oldPriceAvTimestamp;
        uint256 newPriceAvIn;
        uint256 newPriceAvOut;
    }

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
    event SucessfullSwap(uint256 wstEthAmount);

    /**
     * @notice Emitted when the swap from wstETH to WETH fails
     * @param wstEthAmount The amount of wstETH attempted to be swapped
     */
    event FailedWstEthSwap(uint256 wstEthAmount);

    /**
     * @notice Emitted when the swap from WETH to SDEX fails
     * @param wEthAmount The amount of WETH attempted to be swapped
     */
    event FailedWEthSwap(uint256 wEthAmount);

    /**
     * @notice Emitted when the TWAP interval is updated
     * @param newTwapInterval The new TWAP interval
     */
    event TwapIntervalUpdated(uint32 newTwapInterval);

    /**
     * @notice Emitted when the Uniswap pair address is updated
     * @param newPair The new pair address
     */
    event UniswapPairUpdated(address newPair);

    /**
     * @notice Emitted when the Uniswap fee tier is updated
     * @param newFeeTier The new fee tier
     */
    event UniswapFeeTierUpdated(uint24 newFeeTier);

    /**
     * @notice Emitted when the swap slippage percentage is updated
     * @param newSwapSlippage The new swap slippage percentage
     */
    event SwapSlippageUpdated(uint256 newSwapSlippage);

    /* -------------------------------------------------------------------------- */
    /*                                   Errors                                   */
    /* -------------------------------------------------------------------------- */

    /// @notice Thrown when an empty swap path is provided.
    error AutoSwapperInvalidPath();

    /// @notice Thrown when the last token in the path is not SDEX.
    error AutoSwapperInvalidLastToken();

    /// @notice Thrown when a swap is attempted with zero amount.
    error AutoSwapperInvalidAmount();

    /// @notice Thrown when the TWAP interval is set to zero.
    error AutoSwapperInvalidTwapInterval();

    /// @notice Thrown when an invalid Uniswap pair address is set.
    error AutoSwapperInvalidPairAddress();

    /// @notice Thrown when the Uniswap fee tier is invalid
    error AutoSwapperInvalidUniswapFee();

    /// @notice Thrown when slippage configuration is invalid.
    error AutoSwapperInvalidSwapSlippage();

    /// @notice Thrown when the calculated minimum amount out after slippage is zero.
    error AutoSwapperInvalidSlippageCalculation();

    /// @notice Thrown when a caller is not authorized to perform the requested action.
    error AutoSwapperUnauthorized();
}

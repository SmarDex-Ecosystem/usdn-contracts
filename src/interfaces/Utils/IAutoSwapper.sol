// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import { ISmardexPair } from "@smardex-dex-contracts/contracts/ethereum/core/v2/interfaces/ISmardexPair.sol";

/**
 * @title IAutoSwapper
 * @notice Interface for the AutoSwapper contract that provides automated token swapping functionality.
 * @dev Handles token swaps via SmarDex and Uniswap V3 with price protection mechanisms.
 */
interface IAutoSwapper {
    /**
     * @notice Swap parameters used by function _swapAndSend.
     * @param balanceIn Balance of in-token to be swapped.
     * @param pair Pair address.
     * @param fictiveReserve0 Fictive reserve of token0 of the pair.
     * @param fictiveReserve1 Fictive reserve of token1 of the pair.
     * @param oldPriceAv0 Price average of token0 of the pair before the swap.
     * @param oldPriceAv1 Price average of token1 of the pair before the swap.
     * @param oldPriceAvTimestamp Price average of last timestamp of the pair before the swap.
     * @param newPriceAvIn Price average of token0 of the pair after the swap.
     * @param newPriceAvOut Price average of token1 of the pair after the swap.
     */
    struct SwapCallParams {
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
     * @notice Function to swap token in SDEX.
     * @dev Can only be called by the owner.
     * @param amountToSwap Amount of tokens from _path[0] to be converted into SDEX.
     * @param amountOutMin The minimum SDEX amount required to prevent the transaction from reverting.
     * @param path An array of token addresses.
     * @param command Instruction for router to excecute.
     */
    function swapTokenWithPath(uint256 amountToSwap, uint256 amountOutMin, address[] calldata path, uint8 command)
        external;

    /**
     * @notice Swaps wstETH to WETH via Uniswap V3.
     * @param wstEthAmount Amount of wstETH to swap.
     */
    function safeSwapV3(uint256 wstEthAmount) external;

    /**
     * @notice Swaps WETH to SDEX via the Universal Router.
     * @param wethAmount Amount of wstETH to swap.
     */
    function safeSwapSmarDex(uint256 wethAmount) external;

    /**
     * @notice Updates the Uniswap V3 fee tier used when constructing the swap path.
     * @param feeTier The new fee tier.
     */
    function updateUniswapFeeTier(uint24 feeTier) external;

    /**
     * @notice Updates the address of the Uniswap pool used for TWAP calculations.
     * @param newPair The new Uniswap pool address.
     */
    function updateUniswapPair(address newPair) external;

    /**
     * @notice Updates the TWAP interval used for price calculations.
     * @param newTwapInterval The new interval in seconds.
     */
    function updateTwapInterval(uint32 newTwapInterval) external;

    /**
     * @notice Updates the allowed slippage percentage for swaps.
     * @param swapSlippage The new slippage value (in percent, e.g., 2 for 2%).
     * @dev Reverts if the provided slippage is zero.
     */
    function updateSwapSlippage(uint256 swapSlippage) external;

    /**
     * @notice Updates the SmarDex LP fee.
     * @param newFeesLP New LP fee.
     */
    function updateSmardexFeesLP(uint128 newFeesLP) external;

    /**
     * @notice Updates the SmarDex protocol fee.
     * @param newFeesPool New protocol fee.
     */
    function updateSmardexFeesPool(uint128 newFeesPool) external;

    /* -------------------------------------------------------------------------- */
    /*                                   Events                                   */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice Emitted when the swap from wstETH to SDEX completes successfully.
     * @param wstEthAmount The amount of wstETH that was swapped.
     */
    event SucessfullSwap(uint256 wstEthAmount);

    /**
     * @notice Emitted when the swap from wstETH to WETH fails.
     * @param wstEthAmount The amount of wstETH attempted to be swapped.
     */
    event FailedWstEthSwap(uint256 wstEthAmount);

    /**
     * @notice Emitted when the swap from WETH to SDEX fails.
     * @param wEthAmount The amount of WETH attempted to be swapped.
     */
    event FailedWEthSwap(uint256 wEthAmount);

    /**
     * @notice Emitted when the TWAP interval is updated.
     * @param newTwapInterval The new TWAP interval.
     */
    event TwapIntervalUpdated(uint32 newTwapInterval);

    /**
     * @notice Emitted when the Uniswap pair address is updated.
     * @param newPair The new pair address.
     */
    event UniswapPairUpdated(address newPair);

    /**
     * @notice Emitted when the Uniswap fee tier is updated.
     * @param newFeeTier The new fee tier.
     */
    event UniswapFeeTierUpdated(uint24 newFeeTier);

    /**
     * @notice Emitted when the swap slippage percentage is updated.
     * @param newSwapSlippage The new swap slippage percentage.
     */
    event SwapSlippageUpdated(uint256 newSwapSlippage);

    /**
     * @notice Emitted when the SmarDex LP fee is updated.
     * @param newFeesLP The new LP fee.
     */
    event SmardexFeesLPUpdated(uint128 newFeesLP);

    /**
     * @notice Emitted when the SmarDex protocol fee is updated.
     * @param newFeesPool The new protocol fee.
     */
    event SmardexFeesPoolUpdated(uint128 newFeesPool);

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

    /// @notice Thrown when the combined SmarDex fees exceed the maximum allowed.
    error AutoSwapperFeesExceedMaximum();
}

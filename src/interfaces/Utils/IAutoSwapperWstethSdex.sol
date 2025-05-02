// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.0;

import { ISmardexPair } from "@smardex-dex-contracts/contracts/ethereum/core/v2/interfaces/ISmardexPair.sol";

/**
 * @title IAutoSwapperWstethSdex
 * @notice Interface for the AutoSwapperWstethSdex contract that provides automated token swapping functionality.
 * @dev Handles token swaps via SmarDex and Uniswap V3 with price protection mechanisms.
 */
interface IAutoSwapperWstethSdex {
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

    /// @notice Thrown when slippage configuration is invalid.
    error AutoSwapperInvalidSwapSlippage();

    /// @notice Thrown when the caller is not authorized to perform the operation.
    error AutoSwapperInvalidCaller();
}

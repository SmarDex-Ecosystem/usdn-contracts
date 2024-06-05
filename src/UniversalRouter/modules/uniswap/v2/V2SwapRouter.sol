// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import { IUniswapV2Pair } from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import { UniswapV2Library } from "@uniswap/universal-router/contracts/modules/uniswap/v2/UniswapV2Library.sol";
import { UniswapImmutables } from "@uniswap/universal-router/contracts/modules/uniswap/UniswapImmutables.sol";
import { Constants } from "@uniswap/universal-router/contracts/libraries/Constants.sol";
import { Permit2Payments } from "@uniswap/universal-router/contracts/modules/Permit2Payments.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title Router for Uniswap v2 Trades
abstract contract V2SwapRouter is UniswapImmutables, Permit2Payments {
    /// @notice Error emitted when the amount received is too low
    error V2TooLittleReceived();
    /// @notice Error emitted when the amount requested is too high
    error V2TooMuchRequested();
    /// @notice Error emitted when the path is invalid
    error V2InvalidPath();

    /**
     * @dev Structure to hold the data for a swap
     * @param input The input token address
     * @param output The output token address
     * @param nextPair The next pair to swap to
     * @param reserve0 The reserve0 of the pair
     * @param reserve1 The reserve1 of the pair
     * @param reserveInput The reserve of the input token
     * @param reserveOutput The reserve of the output token
     * @param amountInput The amount of input tokens
     * @param amountOutput The amount of output tokens
     * @param amount0Out The amount of token0 to swap
     * @param amount1Out The amount of token1 to swap
     */
    struct V2SwapData {
        address input;
        address output;
        address nextPair;
        uint256 reserve0;
        uint256 reserve1;
        uint256 reserveInput;
        uint256 reserveOutput;
        uint256 amountInput;
        uint256 amountOutput;
        uint256 amount0Out;
        uint256 amount1Out;
    }

    /**
     * @notice Checks if the path is valid and performs the swap
     * @param path The path of the trade as an array of token addresses
     * @param recipient The recipient of the output tokens
     * @param pair The address of the pair to start the swap
     */
    function _v2Swap(address[] calldata path, address recipient, address pair) private {
        unchecked {
            if (path.length < 2) {
                revert V2InvalidPath();
            }

            // cached to save on duplicate operations
            (address token0,) = UniswapV2Library.sortTokens(path[0], path[1]);
            uint256 finalPairIndex = path.length - 1;
            uint256 penultimatePairIndex = finalPairIndex - 1;
            for (uint256 i; i < finalPairIndex; i++) {
                V2SwapData memory data;

                (data.input, data.output) = (path[i], path[i + 1]);

                (data.reserve0, data.reserve1,) = IUniswapV2Pair(pair).getReserves();

                (data.reserveInput, data.reserveOutput) =
                    data.input == token0 ? (data.reserve0, data.reserve1) : (data.reserve1, data.reserve0);

                data.amountInput = IERC20(data.input).balanceOf(pair) - data.reserveInput;

                data.amountOutput =
                    UniswapV2Library.getAmountOut(data.amountInput, data.reserveInput, data.reserveOutput);

                (data.amount0Out, data.amount1Out) =
                    data.input == token0 ? (uint256(0), data.amountOutput) : (data.amountOutput, uint256(0));
                (data.nextPair, token0) = i < penultimatePairIndex
                    ? UniswapV2Library.pairAndToken0For(
                        UNISWAP_V2_FACTORY, UNISWAP_V2_PAIR_INIT_CODE_HASH, data.output, path[i + 2]
                    )
                    : (recipient, address(0));
                IUniswapV2Pair(pair).swap(data.amount0Out, data.amount1Out, data.nextPair, new bytes(0));
                pair = data.nextPair;
            }
        }
    }

    /**
     * @notice Performs a Uniswap v2 exact input swap
     * @param recipient The recipient of the output tokens
     * @param amountIn The amount of input tokens for the trade
     * @param amountOutMinimum The minimum desired amount of output tokens
     * @param path The path of the trade as an array of token addresses
     * @param payer The address that will be paying the input
     */
    function v2SwapExactInput(
        address recipient,
        uint256 amountIn,
        uint256 amountOutMinimum,
        address[] calldata path,
        address payer
    ) internal {
        address firstPair =
            UniswapV2Library.pairFor(UNISWAP_V2_FACTORY, UNISWAP_V2_PAIR_INIT_CODE_HASH, path[0], path[1]);
        if (
            amountIn != Constants.ALREADY_PAID // amountIn of 0 to signal that the pair already has the tokens
        ) {
            payOrPermit2Transfer(path[0], payer, firstPair, amountIn);
        }

        IERC20 tokenOut = IERC20(path[path.length - 1]);
        uint256 balanceBefore = tokenOut.balanceOf(recipient);

        _v2Swap(path, recipient, firstPair);

        uint256 amountOut = tokenOut.balanceOf(recipient) - balanceBefore;
        if (amountOut < amountOutMinimum) {
            revert V2TooLittleReceived();
        }
    }

    /**
     * @notice Performs a Uniswap v2 exact output swap
     * @param recipient The recipient of the output tokens
     * @param amountOut The amount of output tokens to receive for the trade
     * @param amountInMaximum The maximum desired amount of input tokens
     * @param path The path of the trade as an array of token addresses
     * @param payer The address that will be paying the input
     */
    function v2SwapExactOutput(
        address recipient,
        uint256 amountOut,
        uint256 amountInMaximum,
        address[] calldata path,
        address payer
    ) internal {
        (uint256 amountIn, address firstPair) =
            UniswapV2Library.getAmountInMultihop(UNISWAP_V2_FACTORY, UNISWAP_V2_PAIR_INIT_CODE_HASH, amountOut, path);
        if (amountIn > amountInMaximum) {
            revert V2TooMuchRequested();
        }

        payOrPermit2Transfer(path[0], payer, firstPair, amountIn);
        _v2Swap(path, recipient, firstPair);
    }
}

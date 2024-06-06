// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { TransferHelper } from "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";
import { Permit2Payments } from "@uniswap/universal-router/contracts/modules/Permit2Payments.sol";
import { Constants } from "@uniswap/universal-router/contracts/libraries/Constants.sol";

import { ISmardexFactory } from "src/interfaces/UniversalRouter/smardex/ISmardexFactory.sol";
import { ISmardexPair } from "src/interfaces/UniversalRouter/smardex/ISmardexPair.sol";
import { Path } from "src/UniversalRouter/libraries/Path.sol";
import { SmardexImmutables } from "src/UniversalRouter/modules/smardex/SmardexImmutables.sol";
import { ISmardexSwapRouter } from "src/interfaces/UniversalRouter/smardex/ISmardexSwapRouter.sol";

/// @title Router for Smardex
abstract contract SmardexSwapRouter is ISmardexSwapRouter, SmardexImmutables, Permit2Payments {
    /// @notice Indicates that the amountOut is lower than the minAmountOut
    error tooLittleReceived();

    /// @notice Indicates that the amountIn is higher than the maxAmountIn
    error excessiveInputAmount();

    /// @notice Indicates that the recipient is invalid
    error invalidRecipient();

    /// @notice Indicates that msg.sender is not the pair
    error invalidPair();

    /// @notice Indicates that the callback amount is invalid
    error callbackInvalidAmount();

    using Path for bytes;
    using SafeCast for uint256;
    using SafeCast for int256;

    /**
     * @notice callback data for swap from SmardexRouter
     * @param path path of the swap, array of token addresses tightly packed
     * @param payer address of the payer for the swap
     */
    struct SwapCallbackData {
        bytes path;
        address payer;
    }

    /**
     * @dev Used as the placeholder value for maxAmountIn, because the computed amount
     * in for an exact output swap can never actually be this value
     */
    uint256 private constant DEFAULT_MAX_AMOUNT_IN = type(uint256).max;

    /// @dev Transient storage variable used for checking slippage
    uint256 private amountInCached = DEFAULT_MAX_AMOUNT_IN;

    /// @inheritdoc ISmardexSwapRouter
    function smardexSwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata data) external {
        if (amount0Delta <= 0 && amount1Delta <= 0) {
            revert callbackInvalidAmount();
        }

        SwapCallbackData memory decodedData = abi.decode(data, (SwapCallbackData));
        (address tokenIn, address tokenOut) = decodedData.path.decodeFirstPool();

        // ensure that msg.sender is a pair
        if (msg.sender != ISmardexFactory(SMARDEX_FACTORY).getPair(tokenIn, tokenOut)) {
            revert invalidPair();
        }

        (bool isExactInput, uint256 amountToPay) =
            amount0Delta > 0 ? (tokenIn < tokenOut, uint256(amount0Delta)) : (tokenOut < tokenIn, uint256(amount1Delta));

        if (isExactInput) {
            _payOrPermit2Transfer(tokenIn, decodedData.payer, msg.sender, amountToPay);
        } else if (decodedData.path.hasMultiplePools()) {
            decodedData.path = decodedData.path.skipTokenMemory();
            _swapExactOut(amountToPay, msg.sender, decodedData);
        } else {
            amountInCached = amountToPay;
            tokenIn = tokenOut; // swap in/out because exact output swaps are reversed
            _payOrPermit2Transfer(tokenIn, decodedData.payer, msg.sender, amountToPay);
        }
    }

    /**
     * @notice Performs a Smardex exact input swap
     * @dev Use router balance if payer is the router or use permit2 from msg.sender
     * @param recipient The recipient of the output tokens
     * @param amountIn The amount of input tokens for the trade
     * @param amountOutMinimum The minimum desired amount of output tokens
     * @param path The path of the trade as a bytes string
     * @param payer The address that will be paying the input
     */
    function _smardexSwapExactInput(
        address recipient,
        uint256 amountIn,
        uint256 amountOutMinimum,
        bytes calldata path,
        address payer
    ) internal {
        // use amountIn == Constants.CONTRACT_BALANCE as a flag to swap the entire balance of the contract
        if (amountIn == Constants.CONTRACT_BALANCE) {
            address tokenIn = path.decodeFirstToken();
            amountIn = IERC20(tokenIn).balanceOf(address(this));
        }

        uint256 amountOut;
        while (true) {
            bool hasMultiplePools = path.hasMultiplePools();
            amountIn = _swapExactIn(
                amountIn,
                // for intermediate swaps, this contract custodies
                hasMultiplePools ? address(this) : recipient,
                // only the first pool in the path is necessary
                SwapCallbackData({ path: path.getFirstPool(), payer: payer })
            );

            // decide whether to continue or terminate
            if (hasMultiplePools) {
                payer = address(this);
                path = path.skipToken();
            } else {
                amountOut = amountIn;
                break;
            }
        }

        if (amountOut < amountOutMinimum) {
            revert tooLittleReceived();
        }
    }

    /**
     * @notice Performs a Smardex exact output swap
     * @dev Use router balance if payer is the router or use permit2 from msg.sender
     * @param recipient The recipient of the output tokens
     * @param amountOut The amount of output tokens to receive for the trade
     * @param amountInMaximum The maximum desired amount of input tokens
     * @param path The path of the trade as a bytes string
     * @param payer The address that will be paying the input
     */
    function _smardexSwapExactOutput(
        address recipient,
        uint256 amountOut,
        uint256 amountInMaximum,
        bytes calldata path,
        address payer
    ) internal {
        amountInCached = amountInMaximum;
        // Path needs to be reversed as to get the amountIn that we will ask from next pair hop
        bytes memory _reversedPath = path.encodeTightlyPackedReversed();
        uint256 amountIn = _swapExactOut(amountOut, recipient, SwapCallbackData({ path: _reversedPath, payer: payer }));
        // amount In is only the right one for one Hop, otherwise we need cached amountIn from callback
        if (path.length > 2) {
            amountIn = amountInCached;
        }

        if (amountIn > amountInMaximum) {
            revert excessiveInputAmount();
        }
        amountInCached = DEFAULT_MAX_AMOUNT_IN;
    }

    /**
     * @notice internal function to swap quantity of token to receive a determined quantity
     * @param amountOut quantity to receive
     * @param to address that will receive the token
     * @param data SwapCallbackData data of the swap to transmit
     * @return amountIn_ amount of token to pay
     */
    function _swapExactOut(uint256 amountOut, address to, SwapCallbackData memory data)
        private
        returns (uint256 amountIn_)
    {
        if (to == address(0)) {
            revert invalidRecipient();
        }

        (address tokenOut, address tokenIn) = data.path.decodeFirstPool();
        bool zeroForOne = tokenIn < tokenOut;

        (int256 amount0, int256 amount1) = ISmardexPair(ISmardexFactory(SMARDEX_FACTORY).getPair(tokenIn, tokenOut))
            .swap(to, zeroForOne, -amountOut.toInt256(), abi.encode(data));

        if (zeroForOne) {
            amountIn_ = uint256(amount0);
        } else {
            amountIn_ = uint256(amount1);
        }
    }

    /**
     * @notice internal function to swap a determined quantity of token
     * @param amountIn quantity to swap
     * @param to address that will receive the token
     * @param data SwapCallbackData data of the swap to transmit
     * @return amountOut_ amount of token that _to will receive
     */
    function _swapExactIn(uint256 amountIn, address to, SwapCallbackData memory data)
        internal
        returns (uint256 amountOut_)
    {
        // allow swapping to the router address with address 0
        if (to == address(0)) {
            to = address(this);
        }

        (address tokenIn, address tokenOut) = data.path.decodeFirstPool();
        bool _zeroForOne = tokenIn < tokenOut;
        (int256 amount0, int256 amount1) = ISmardexPair(ISmardexFactory(SMARDEX_FACTORY).getPair(tokenIn, tokenOut))
            .swap(to, _zeroForOne, amountIn.toInt256(), abi.encode(data));
        amountOut_ = (_zeroForOne ? -amount1 : -amount0).toUint256();
    }

    /**
     * @notice Either performs a regular payment or transferFrom on Permit2, depending on the payer address
     * @param token The token to transfer
     * @param payer The address to pay for the transfer
     * @param recipient The recipient of the transfer
     * @param amount The amount to transfer
     */
    function _payOrPermit2Transfer(address token, address payer, address recipient, uint256 amount) internal {
        if (payer == address(this)) {
            TransferHelper.safeTransfer(token, recipient, amount);
        } else {
            permit2TransferFrom(token, payer, recipient, amount.toUint160());
        }
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { TransferHelper } from "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";
import { Permit2Payments } from "@uniswap/universal-router/contracts/modules/Permit2Payments.sol";
import { Constants } from "@uniswap/universal-router/contracts/libraries/Constants.sol";
import { V3Path } from "@uniswap/universal-router/contracts/modules/uniswap/v3/V3Path.sol";

import { ISmardexFactory } from "src/UniversalRouter/interfaces/ISmardexFactory.sol";
import { ISmardexPair } from "src/UniversalRouter/interfaces/ISmardexPair.sol";
import { Path } from "src/UniversalRouter/libraries/Path.sol";
import { SmardexImmutables } from "src/UniversalRouter/modules/smardex/SmardexImmutables.sol";

/// @title Router for Smardex
abstract contract SmardexSwapRouter is SmardexImmutables, Permit2Payments {
    /**
     * @notice Indicates that the amount received by a smardex
     * swapExactIn is lower than the minimum expected amount
     */
    error tooLittleReceived();

    using Path for bytes;
    using Path for address[];
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

    /**
     * @notice callback data for smardex swap
     * @param _amount0Delta amount of token0 for the swap (negative is incoming, positive is required to pay to pair)
     * @param _amount1Delta amount of token1 for the swap (negative is incoming, positive is required to pay to pair)
     * @param _data for Router path and payer for the swap
     */
    function smardexSwapCallback(int256 _amount0Delta, int256 _amount1Delta, bytes calldata _data) external {
        require(_amount0Delta > 0 || _amount1Delta > 0, "SmardexRouter: Callback Invalid amount");

        SwapCallbackData memory _decodedData = abi.decode(_data, (SwapCallbackData));
        (address _tokenIn, address _tokenOut) = _decodedData.path.decodeFirstPool();

        // ensure that msg.sender is a pair
        require(
            msg.sender == ISmardexFactory(SMARDEX_FACTORY).getPair(_tokenIn, _tokenOut), "SmarDexRouter: INVALID_PAIR"
        );

        (bool _isExactInput, uint256 _amountToPay) = _amount0Delta > 0
            ? (_tokenIn < _tokenOut, uint256(_amount0Delta))
            : (_tokenOut < _tokenIn, uint256(_amount1Delta));

        if (_isExactInput) {
            _payOrPermit2Transfer(_tokenIn, _decodedData.payer, msg.sender, _amountToPay);
        } else if (_decodedData.path.hasMultiplePools()) {
            _decodedData.path = _decodedData.path.skipTokenMemory();
            _swapExactOut(_amountToPay, msg.sender, _decodedData);
        } else {
            amountInCached = _amountToPay;
            _tokenIn = _tokenOut; // swap in/out because exact output swaps are reversed
            _payOrPermit2Transfer(_tokenIn, _decodedData.payer, msg.sender, _amountToPay);
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
    function smardexSwapExactInput(
        address recipient,
        uint256 amountIn,
        uint256 amountOutMinimum,
        bytes calldata path,
        address payer
    ) internal {
        // use amountIn == Constants.CONTRACT_BALANCE as a flag to swap the entire balance of the contract
        if (amountIn == Constants.CONTRACT_BALANCE) {
            address tokenIn = V3Path.decodeFirstToken(path);
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
                path = Path.skipToken(path);
            } else {
                amountOut = amountIn;
                break;
            }
        }

        if (amountOut < amountOutMinimum) revert tooLittleReceived();
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
    function smardexSwapExactOutput(
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
        if (path.length > 2) amountIn = amountInCached;
        require(amountIn <= amountInMaximum, "SmarDexRouter: EXCESSIVE_INPUT_AMOUNT");
        amountInCached = DEFAULT_MAX_AMOUNT_IN;
    }

    /**
     * @notice internal function to swap quantity of token to receive a determined quantity
     * @param _amountOut quantity to receive
     * @param _to address that will receive the token
     * @param _data SwapCallbackData data of the swap to transmit
     * @return amountIn_ amount of token to pay
     */
    function _swapExactOut(uint256 _amountOut, address _to, SwapCallbackData memory _data)
        private
        returns (uint256 amountIn_)
    {
        require(_to != address(0), "SmarDexRouter: INVALID_RECIPIENT");

        (address _tokenOut, address _tokenIn) = _data.path.decodeFirstPool();
        bool _zeroForOne = _tokenIn < _tokenOut;

        (int256 _amount0, int256 _amount1) = ISmardexPair(ISmardexFactory(SMARDEX_FACTORY).getPair(_tokenIn, _tokenOut))
            .swap(_to, _zeroForOne, -_amountOut.toInt256(), abi.encode(_data));

        amountIn_ = _zeroForOne ? uint256(_amount0) : uint256(_amount1);
    }

    /**
     * @notice internal function to swap a determined quantity of token
     * @param _amountIn quantity to swap
     * @param _to address that will receive the token
     * @param _data SwapCallbackData data of the swap to transmit
     * @return amountOut_ amount of token that _to will receive
     */
    function _swapExactIn(uint256 _amountIn, address _to, SwapCallbackData memory _data)
        internal
        returns (uint256 amountOut_)
    {
        // allow swapping to the router address with address 0
        if (_to == address(0)) {
            _to = address(this);
        }

        (address _tokenIn, address _tokenOut) = _data.path.decodeFirstPool();
        bool _zeroForOne = _tokenIn < _tokenOut;
        (int256 _amount0, int256 _amount1) = ISmardexPair(ISmardexFactory(SMARDEX_FACTORY).getPair(_tokenIn, _tokenOut))
            .swap(_to, _zeroForOne, _amountIn.toInt256(), abi.encode(_data));
        amountOut_ = (_zeroForOne ? -_amount1 : -_amount0).toUint256();
    }

    /**
     * @notice send tokens to a user. Handle transfer/transferFrom and WETH / ETH or any ERC20 token
     * @param _token The token to pay
     * @param _payer The entity that must pay
     * @param _to The entity that will receive payment
     * @param _value The amount to pay
     * @custom:from UniV3 PeripheryPayments.sol
     * @custom:url https://github.com/Uniswap/v3-periphery/blob/v1.3.0/contracts/base/PeripheryPayments.sol
     */
    function _pay(address _token, address _payer, address _to, uint256 _value) internal {
        if (_token == address(WETH) && address(this).balance >= _value) {
            // pay with WETH
            WETH.deposit{ value: _value }(); // wrap only what is needed to pay
            WETH.transfer(_to, _value);
            //refund dust eth, if any ?
        } else if (_payer == address(this)) {
            // pay with tokens already in the contract (for the exact input multihop case)
            TransferHelper.safeTransfer(_token, _to, _value);
        } else {
            // pull payment
            TransferHelper.safeTransferFrom(_token, _payer, _to, _value);
        }
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
            _pay(token, address(this), recipient, amount);
        } else {
            permit2TransferFrom(token, payer, recipient, amount.toUint160());
        }
    }
}

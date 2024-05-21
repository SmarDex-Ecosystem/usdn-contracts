// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import { SmardexImmutables } from "src/UniversalRouter/modules/smardex/SmardexImmutables.sol";
import { Constants } from "@uniswap/universal-router/contracts/libraries/Constants.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import { Permit2Payments } from "@uniswap/universal-router/contracts/modules/Permit2Payments.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ISmardexFactory } from "src/UniversalRouter/interfaces/ISmardexFactory.sol";
import { ISmardexPair } from "src/UniversalRouter/interfaces/ISmardexPair.sol";
import { IWETH } from "src/UniversalRouter/interfaces/IWETH.sol";
import { TransferHelper } from "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";
import { Path } from "src/UniversalRouter/libraries/Path.sol";

/// @title Router for Smardex
abstract contract SmardexSwapRouter is SmardexImmutables, Permit2Payments {
    using Path for bytes;
    using SafeCast for uint256;

    /**
     * @notice callback data for swap from SmardexRouter
     * @param path path of the swap, array of token addresses tightly packed
     * @param payer address of the payer for the swap
     */
    struct SwapCallbackData {
        bytes path;
        address payer;
    }

    uint256 amountInCached;

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
            _decodedData.path = _decodedData.path.skipToken();
            _swapExactOut(_amountToPay, msg.sender, _decodedData);
        } else {
            amountInCached = _amountToPay;
            _tokenIn = _tokenOut; // swap in/out because exact output swaps are reversed
            _payOrPermit2Transfer(_tokenIn, _decodedData.payer, msg.sender, _amountToPay);
        }
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
     * @notice send tokens to a user. Handle transfer/transferFrom and WETH / ETH or any ERC20 token
     * @param _token The token to pay
     * @param _payer The entity that must pay
     * @param _to The entity that will receive payment
     * @param _value The amount to pay
     *
     * @custom:from UniV3 PeripheryPayments.sol
     * @custom:url https://github.com/Uniswap/v3-periphery/blob/v1.3.0/contracts/base/PeripheryPayments.sol
     */
    function _pay(address _token, address _payer, address _to, uint256 _value) internal {
        if (_token == WETH && address(this).balance >= _value) {
            // pay with WETH
            IWETH(WETH).deposit{ value: _value }(); // wrap only what is needed to pay
            IWETH(WETH).transfer(_to, _value);
            //refund dust eth, if any ?
        } else if (_payer == address(this)) {
            // pay with tokens already in the contract (for the exact input multihop case)
            TransferHelper.safeTransfer(_token, _to, _value);
        } else {
            // pull payment
            TransferHelper.safeTransferFrom(_token, _payer, _to, _value);
        }
    }

    /// @notice Either performs a regular payment or transferFrom on Permit2, depending on the payer address
    /// @param token The token to transfer
    /// @param payer The address to pay for the transfer
    /// @param recipient The recipient of the transfer
    /// @param amount The amount to transfer
    function _payOrPermit2Transfer(address token, address payer, address recipient, uint256 amount) internal {
        if (payer == address(this)) {
            _pay(token, address(this), recipient, amount);
        } else {
            permit2TransferFrom(token, payer, recipient, amount.toUint160());
        }
    }
}

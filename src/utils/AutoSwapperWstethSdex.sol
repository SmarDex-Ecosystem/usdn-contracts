// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import { Ownable, Ownable2Step } from "@openzeppelin/contracts/access/Ownable2Step.sol";
import { IERC20, SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ERC165 } from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import { IERC165 } from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import { ISmardexPair } from "@smardex-dex-contracts/contracts/ethereum/core/v2/interfaces/ISmardexPair.sol";
import { ISmardexSwapCallback } from
    "@smardex-dex-contracts/contracts/ethereum/core/v2/interfaces/ISmardexSwapCallback.sol";
import { SmardexLibrary } from "@smardex-dex-contracts/contracts/ethereum/core/v2/libraries/SmardexLibrary.sol";
import { IUniswapV3Pool } from "@uniswapV3/contracts/interfaces/IUniswapV3Pool.sol";
import { IUniswapV3SwapCallback } from "@uniswapV3/contracts/interfaces/callback/IUniswapV3SwapCallback.sol";

import { IWstETH } from "./../interfaces/IWstETH.sol";
import { IFeeCollectorCallback } from "./../interfaces/UsdnProtocol/IFeeCollectorCallback.sol";
import { IAutoSwapperWstethSdex } from "./../interfaces/Utils/IAutoSwapperWstethSdex.sol";

/**
 * @title SDEX buy-back and burn Autoswapper
 * @notice Automates protocol fee conversion from wstETH to SDEX via Uniswap V3 and Smardex.
 */
contract AutoSwapperWstethSdex is
    Ownable2Step,
    IAutoSwapperWstethSdex,
    IFeeCollectorCallback,
    ERC165,
    ISmardexSwapCallback,
    IUniswapV3SwapCallback
{
    using SafeERC20 for IERC20;
    using SafeERC20 for IWstETH;

    /// @notice Decimal points for basis points (bps).
    uint16 internal constant BPS_DIVISOR = 10_000;

    /// @notice Wrapped staked ETH token address.
    IWstETH internal constant WSTETH = IWstETH(0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0);

    /// @notice Wrapped ETH token address.
    IERC20 internal constant WETH = IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

    /// @notice SmarDex pair address for WETH/SDEX swaps.
    ISmardexPair internal constant SMARDEX_WETH_SDEX_PAIR = ISmardexPair(0xf3a4B8eFe3e3049F6BC71B47ccB7Ce6665420179);

    /// @notice Uniswap V3 pair address for WSTETH/WETH swaps.
    IUniswapV3Pool internal constant UNI_WSTETH_WETH_PAIR = IUniswapV3Pool(0x109830a1AAaD605BbF02a9dFA7B0B92EC2FB7dAa);

    /// @notice Allowed slippage for swaps (in basis points).
    uint256 internal _swapSlippage = 100; // 1%

    constructor() Ownable(msg.sender) { }

    /// @inheritdoc IFeeCollectorCallback
    function feeCollectorCallback(uint256) external {
        try this.swapWstethToSdex() { }
        catch {
            emit FailedSwap();
        }
    }

    /// @inheritdoc IAutoSwapperWstethSdex
    function swapWstethToSdex() external {
        _uniWstethToWeth();
        _smarDexWethToSdex();
    }

    /// @inheritdoc IUniswapV3SwapCallback
    function uniswapV3SwapCallback(int256 amountWstethIn, int256, bytes calldata) external {
        if (msg.sender != address(UNI_WSTETH_WETH_PAIR)) {
            revert AutoSwapperInvalidCaller();
        }

        WSTETH.safeTransfer(msg.sender, uint256(amountWstethIn));
    }

    /// @inheritdoc ISmardexSwapCallback
    function smardexSwapCallback(int256, int256 amountWethIn, bytes calldata) external {
        if (msg.sender != address(SMARDEX_WETH_SDEX_PAIR)) {
            revert AutoSwapperInvalidCaller();
        }

        WETH.safeTransfer(msg.sender, uint256(amountWethIn));
    }

    /// @inheritdoc IAutoSwapperWstethSdex
    function sweep(address token, address to, uint256 amount) external onlyOwner {
        IERC20(token).safeTransfer(to, amount);
    }

    /// @inheritdoc IAutoSwapperWstethSdex
    function updateSwapSlippage(uint256 newSwapSlippage) external onlyOwner {
        if (newSwapSlippage == 0) {
            revert AutoSwapperInvalidSwapSlippage();
        }
        _swapSlippage = newSwapSlippage;
        emit SwapSlippageUpdated(newSwapSlippage);
    }

    /// @inheritdoc ERC165
    function supportsInterface(bytes4 interfaceId) public view override(ERC165, IERC165) returns (bool) {
        if (interfaceId == type(IFeeCollectorCallback).interfaceId) {
            return true;
        }

        return super.supportsInterface(interfaceId);
    }

    /// @notice Swaps wstETH for WETH on Uniswap V3.
    function _uniWstethToWeth() internal {
        uint256 wstEthAmount = WSTETH.balanceOf(address(this));

        (, int256 amountWethOut) =
        // 4_295_128_740 is equivalent to getSqrtRatioAtTick(MIN_TICK) -> unlimited slippage.
         UNI_WSTETH_WETH_PAIR.swap(address(this), true, int256(wstEthAmount), 4_295_128_740, "");

        uint256 minWethAmount = WSTETH.getStETHByWstETH(wstEthAmount) * (BPS_DIVISOR - _swapSlippage) / BPS_DIVISOR;

        if (uint256(-amountWethOut) < minWethAmount) {
            revert AutoSwapperSwapFailed();
        }
    }

    /// @notice Swaps WETH for SDEX token using the SmarDex protocol.
    function _smarDexWethToSdex() internal {
        uint256 wethAmount = WETH.balanceOf(address(this));

        uint256 newPriceAvWeth;
        uint256 newPriceAvSdex;
        (uint256 fictiveReserveSdex, uint256 fictiveReserveWeth) = SMARDEX_WETH_SDEX_PAIR.getFictiveReserves();
        {
            (uint256 oldPriceAvSdex, uint256 oldPriceAvWeth, uint256 oldPriceAvTimestamp) =
                SMARDEX_WETH_SDEX_PAIR.getPriceAverage();

            (newPriceAvWeth, newPriceAvSdex) = SmardexLibrary.getUpdatedPriceAverage(
                fictiveReserveWeth,
                fictiveReserveSdex,
                oldPriceAvTimestamp,
                oldPriceAvWeth,
                oldPriceAvSdex,
                block.timestamp
            );
        }

        (uint256 reservesSdex, uint256 reservesWeth) = SMARDEX_WETH_SDEX_PAIR.getReserves();
        (uint256 avAmountSdexOut,,,,) = SmardexLibrary.getAmountOut(
            SmardexLibrary.GetAmountParameters({
                amount: wethAmount,
                reserveIn: reservesWeth,
                reserveOut: reservesSdex,
                fictiveReserveIn: fictiveReserveWeth,
                fictiveReserveOut: fictiveReserveSdex,
                priceAverageIn: newPriceAvWeth,
                priceAverageOut: newPriceAvSdex,
                // SmarDex LP fee for v1 pools
                feesLP: 500,
                // SmarDex pool fee for v1 pools.
                feesPool: 200
            })
        );

        uint256 minSdexAmount = avAmountSdexOut * (BPS_DIVISOR - _swapSlippage) / BPS_DIVISOR;

        (int256 amountSdexOut,) = SMARDEX_WETH_SDEX_PAIR.swap(address(0xdead), false, int256(wethAmount), "");

        if (uint256(-amountSdexOut) < minSdexAmount) {
            revert AutoSwapperSwapFailed();
        }
    }
}

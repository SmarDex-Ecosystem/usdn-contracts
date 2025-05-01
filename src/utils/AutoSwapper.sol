// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import { Ownable, Ownable2Step } from "@openzeppelin/contracts/access/Ownable2Step.sol";
import { IERC20, SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { ERC165 } from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import { IERC165 } from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import { ISmardexPair } from "@smardex-dex-contracts/contracts/ethereum/core/v2/interfaces/ISmardexPair.sol";
import { SmardexLibrary } from "@smardex-dex-contracts/contracts/ethereum/core/v2/libraries/SmardexLibrary.sol";
import { IUniversalRouter } from "@smardex-universal-router/src/interfaces/IUniversalRouter.sol";
import { IAllowanceTransfer } from "@uniswap/permit2/src/interfaces/IAllowanceTransfer.sol";
// to do : check this import
import { IUniswapV3Pool } from "@uniswapV3/contracts/interfaces/IUniswapV3Pool.sol";
import { TickMath } from "@uniswapV3/contracts/libraries/TickMath.sol";

import { IWstETH } from "./../interfaces/IWstETH.sol";
import { IFeeCollectorCallback } from "./../interfaces/UsdnProtocol/IFeeCollectorCallback.sol";
import { IAutoSwapper } from "./../interfaces/Utils/IAutoSwapper.sol";

/**
 * @title AutoSwapper
 * @notice Automates protocol fee conversion from wstETH to SDEX via Uniswap V3 and Smardex.
 */
contract AutoSwapper is Ownable2Step, ReentrancyGuard, IAutoSwapper, IFeeCollectorCallback, ERC165 {
    using SafeERC20 for IERC20;
    using SafeERC20 for IWstETH;

    /* -------------------------------------------------------------------------- */
    /*                                  Constants                                 */
    /* -------------------------------------------------------------------------- */

    uint16 internal constant BPS_DIVISOR = 10_000;

    /// @notice Uniswap V3 command code for exact input swap.
    uint8 private constant V3_SWAP_EXACT_IN = 0x00;

    /// @notice SmarDex command code for exact input swap.
    uint8 private constant SMARDEX_SWAP_EXACT_IN = 0x38;

    /// @notice Burn address for receiving output tokens.
    address internal constant DEAD_ADDRESS = 0x000000000000000000000000000000000000dEaD;

    /// @notice Permit2 contract used for token approvals with signatures.
    IAllowanceTransfer constant PERMIT2 = IAllowanceTransfer(0x000000000022D473030F116dDEE9F6B43aC78BA3);

    ISmardexPair constant SMARDEX_WETH_SDEX_PAIR = ISmardexPair(0xf3a4B8eFe3e3049F6BC71B47ccB7Ce6665420179);

    /// @notice Wrapped staked ETH token used as input for swaps.
    IWstETH internal constant WSTETH = IWstETH(0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0);

    /// @notice Wrapped ETH token received from Uniswap V3 swaps.
    IERC20 internal constant WETH = IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

    /// @notice Final output token after SmarDex swap.
    IERC20 internal constant SDEX = IERC20(0x5DE8ab7E27f6E7A1fFf3E5B337584Aa43961BEeF);

    /// @notice Universal Router instance for performing multi-hop swaps.
    IUniversalRouter internal immutable _router;

    bool internal UNISWAP_ZERO_FOR_ONE;
    bool internal SMARDEX_ZERO_FOR_ONE;

    /// @notice Uniswap V3 pool used for wstETH → WETH swap.
    address internal constant UNI_WSTETH_WETH_PAIR = 0x109830a1AAaD605BbF02a9dFA7B0B92EC2FB7dAa;

    /// @notice Allowed slippage percentage for Uniswap V3 swaps.
    uint256 internal _swapSlippage = 100; // 1%

    /// @notice SmarDex LP fee (700 = 0.07% of FEES_BASE 1,000,000)
    uint128 internal constant SMARDEX_FEE_LP = 700;

    /// @notice SmarDex protocol fee (200 = 0.02% of FEES_BASE 1,000,000)
    uint128 internal constant SMARDEX_FEE_POOL = 200;

    /// @notice Fee tier used for Uniswap V3 path.
    uint24 internal constant UNISWAP_FEE_TIER = 1; // 0.01% fee tier

    /**
     * @param router Address of the Universal Router.
     */
    constructor(address router) Ownable(msg.sender) {
        _router = IUniversalRouter(router);
        UNISWAP_ZERO_FOR_ONE = WSTETH < WETH;
        SMARDEX_ZERO_FOR_ONE = WETH < SDEX;
    }

    /// @inheritdoc ERC165
    function supportsInterface(bytes4 interfaceId) public view override(ERC165, IERC165) returns (bool) {
        if (interfaceId == type(IFeeCollectorCallback).interfaceId) {
            return true;
        }
        return super.supportsInterface(interfaceId);
    }

    /// @inheritdoc IFeeCollectorCallback
    function feeCollectorCallback(uint256) external override nonReentrant {
        _processSwap();
    }

    /**
     * @notice Executes a two-step swap: wstETH --> WETH --> SDEX.
     * @dev If the first swap fails, the second is skipped.
     * If the second swap fails, it is silently ignored.
     */
    function _processSwap() internal {
        uint256 wstEthAmount = WSTETH.balanceOf(address(this));
        if (wstEthAmount == 0) {
            revert AutoSwapperInvalidAmount();
        }

        try this.uniWstethToWeth(wstEthAmount) {
            uint256 wethAmount = WETH.balanceOf(address(this));
            try this.smarDexWethToSdex(wethAmount) {
                emit SuccessfulSwap(wstEthAmount);
            } catch {
                emit FailedWEthSwap(wethAmount);
            }
        } catch {
            emit FailedWstEthSwap(wstEthAmount);
        }
    }

    function uniWstethToWeth(uint256 wstethAmount) external {
        (int256 amount0, int256 amount1) = IUniswapV3Pool(UNI_WSTETH_WETH_PAIR).swap(
            address(this),
            UNISWAP_ZERO_FOR_ONE,
            int256(wstethAmount),
            TickMath.getSqrtRatioAtTick(0),
            abi.encode(abi.encodePacked(WSTETH, UNISWAP_FEE_TIER, WETH), msg.sender)
        );

        uint256 amountOut = uint256(-(UNISWAP_ZERO_FOR_ONE ? amount1 : amount0));
        uint256 minAmountOut =
            IWstETH(address(WSTETH)).getStETHByWstETH(wstethAmount) * (BPS_DIVISOR - _swapSlippage) / BPS_DIVISOR;

        require(amountOut >= minAmountOut);
    }

    function uniswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata) external {
        require(msg.sender == UNI_WSTETH_WETH_PAIR, "Caller is not the Uniswap V3 pool");

        uint256 amountToPay = amount0Delta > 0 ? uint256(amount0Delta) : uint256(amount1Delta);
        WSTETH.safeTransfer(msg.sender, amountToPay);
    }

    /**
     * @notice Swaps WETH for SDEX token using the SmarDex protocol
     * @dev Uses Permit2 for approvals, calculates minimum output with slippage protection
     * @param wethAmount Amount of WETH to swap
     */
    function smarDexWethToSdex(uint256 wethAmount) external {
        SwapCallParams memory _params = SwapCallParams({
            balanceIn: wethAmount,
            pair: SMARDEX_WETH_SDEX_PAIR,
            fictiveReserve0: 0,
            fictiveReserve1: 0,
            oldPriceAv0: 0,
            oldPriceAv1: 0,
            oldPriceAvTimestamp: 0,
            newPriceAvIn: 0,
            newPriceAvOut: 0
        });

        // get reserves and pricesAv
        (_params.fictiveReserve0, _params.fictiveReserve1) = SMARDEX_WETH_SDEX_PAIR.getFictiveReserves();
        (_params.oldPriceAv0, _params.oldPriceAv1, _params.oldPriceAvTimestamp) =
            SMARDEX_WETH_SDEX_PAIR.getPriceAverage();

        (_params.newPriceAvIn, _params.newPriceAvOut) = SmardexLibrary.getUpdatedPriceAverage(
            _params.fictiveReserve1,
            _params.fictiveReserve0,
            _params.oldPriceAvTimestamp,
            _params.oldPriceAv1,
            _params.oldPriceAv0,
            block.timestamp
        );

        (uint256 reservesOut, uint256 reservesIn) = SMARDEX_WETH_SDEX_PAIR.getReserves();

        SmardexLibrary.GetAmountParameters memory smardexParams = SmardexLibrary.GetAmountParameters({
            amount: wethAmount,
            reserveIn: reservesIn,
            reserveOut: reservesOut,
            fictiveReserveIn: _params.fictiveReserve1,
            fictiveReserveOut: _params.fictiveReserve0,
            priceAverageIn: _params.newPriceAvOut,
            priceAverageOut: _params.newPriceAvIn,
            feesLP: SMARDEX_FEE_LP,
            feesPool: SMARDEX_FEE_POOL
        });

        (uint256 amountOut,,,,) = SmardexLibrary.getAmountOut(smardexParams);
        uint256 minAmountOut = amountOut * (BPS_DIVISOR - _swapSlippage) / BPS_DIVISOR;
        uint256 deadAddrBalanceBefore = SDEX.balanceOf(DEAD_ADDRESS);

        SMARDEX_WETH_SDEX_PAIR.swap(DEAD_ADDRESS, SMARDEX_ZERO_FOR_ONE, int256(wethAmount), "");

        require(
            IERC20(SDEX).balanceOf(DEAD_ADDRESS) - deadAddrBalanceBefore >= minAmountOut,
            "AutoSwapper: SmarDex swap failed"
        );
    }

    function smardexSwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata) external {
        require(msg.sender == address(SMARDEX_WETH_SDEX_PAIR), "SmarDexRouter: INVALID_PAIR");

        uint256 amountToPay = amount0Delta > 0 ? uint256(amount0Delta) : uint256(amount1Delta);
        IERC20(WETH).safeTransfer(msg.sender, amountToPay);
    }

    /// @inheritdoc IAutoSwapper
    function swapTokenWithPath(uint256 amountToSwap, uint256 amountOutMin, address[] calldata path, uint8 command)
        external
        onlyOwner
    {
        if (path.length == 0) {
            revert AutoSwapperInvalidPath();
        }
        if (path[path.length - 1] != address(SDEX)) {
            revert AutoSwapperInvalidLastToken();
        }

        IERC20 inputToken = IERC20(path[0]);
        inputToken.safeTransferFrom(msg.sender, address(this), amountToSwap);

        bytes memory commands = abi.encodePacked(command);
        bytes[] memory inputs = new bytes[](1);

        inputs[0] = abi.encode(DEAD_ADDRESS, amountToSwap, amountOutMin, abi.encodePacked(path[0], path[1]), true);

        _permit2Approve(WETH, address(_router), amountToSwap);
        _router.execute(commands, inputs);
    }

    /**
     * @notice Approves the Permit2 contract to transfer tokens and grants Permit2 approval to a spender.
     * @dev Uses SafeCast to ensure proper type conversion for Permit2.
     * @param token The ERC20 token to approve.
     * @param spender The address to be approved to spend tokens via Permit2.
     * @param approveAmount The amount of tokens to approve.
     */
    function _permit2Approve(IERC20 token, address spender, uint256 approveAmount) internal {
        token.approve(address(PERMIT2), approveAmount);
        PERMIT2.approve(address(token), address(spender), uint160(approveAmount), uint48(block.timestamp));
    }

    /// @inheritdoc IAutoSwapper
    function updateSwapSlippage(uint256 newSwapSlippage) external onlyOwner {
        if (newSwapSlippage == 0) {
            revert AutoSwapperInvalidSwapSlippage();
        }
        _swapSlippage = newSwapSlippage;
        emit SwapSlippageUpdated(newSwapSlippage);
    }
}

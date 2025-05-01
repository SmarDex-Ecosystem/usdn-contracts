// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import { Ownable, Ownable2Step } from "@openzeppelin/contracts/access/Ownable2Step.sol";
import { IERC20, SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { ERC165 } from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import { IERC165 } from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { ISmardexFactory } from "@smardex-dex-contracts/contracts/ethereum/core/v2/interfaces/ISmardexFactory.sol";
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
    using SafeCast for uint256;

    /* -------------------------------------------------------------------------- */
    /*                                  Constants                                 */
    /* -------------------------------------------------------------------------- */

    uint16 internal constant BPS_DIVISOR = 10_000;

    /// @notice Uniswap V3 command code for exact input swap.
    uint8 private constant V3_SWAP_EXACT_IN = 0x00;

    /// @notice SmarDex command code for exact input swap.
    uint8 private constant SMARDEX_SWAP_EXACT_IN = 0x38;

    /// @notice Burn address for receiving output tokens.
    address internal constant BURN_ADDRESS = 0x000000000000000000000000000000000000dEaD;

    /// @notice Permit2 contract used for token approvals with signatures.
    IAllowanceTransfer constant PERMIT2 = IAllowanceTransfer(0x000000000022D473030F116dDEE9F6B43aC78BA3);

    /* -------------------------------------------------------------------------- */
    /*                                 Immutables                                 */
    /* -------------------------------------------------------------------------- */

    /// @notice Wrapped staked ETH token used as input for swaps.
    IERC20 internal immutable _wstETH;

    /// @notice Wrapped ETH token received from Uniswap V3 swaps.
    IERC20 internal immutable _wETH;

    /// @notice Final output token after SmarDex swap.
    IERC20 internal immutable _smardexToken;

    /// @notice Universal Router instance for performing multi-hop swaps.
    IUniversalRouter internal immutable _router;

    /// @notice SmarDex factory used to fetch trading pairs for swaps.
    ISmardexFactory internal immutable _factory;

    bool internal ZERO_FOR_ONE;

    /* -------------------------------------------------------------------------- */
    /*                          Admin Configurable Params                         */
    /* -------------------------------------------------------------------------- */

    /// @notice Uniswap V3 pool used for wstETH → WETH swap.
    address internal _uniswapPair;

    /// @notice Allowed slippage percentage for Uniswap V3 swaps.
    uint256 internal _swapSlippage = 100; // 1%

    /// @notice SmarDex LP fee (700 = 0.07% of FEES_BASE 1,000,000)
    uint128 internal _smardexFeesLP = 700;

    /// @notice SmarDex protocol fee (200 = 0.02% of FEES_BASE 1,000,000)
    uint128 internal _smardexFeesPool = 200;

    /// @notice Fee tier used for Uniswap V3 path.
    uint24 internal _uniswapFeeTier = 1; // 0.01% fee tier

    /**
     * @param wstETH Address of the wstETH token.
     * @param wETH Address of the WETH token.
     * @param smardexToken Address of the SDEX token.
     * @param router Address of the Universal Router.
     * @param factory Address of the factory of Smardex..
     * @param uniswapPair Address of the Uniswap Pair.
     */
    constructor(
        address wstETH,
        address wETH,
        address smardexToken,
        address router,
        address factory,
        address uniswapPair
    ) Ownable(msg.sender) {
        _wstETH = IERC20(wstETH);
        _wETH = IERC20(wETH);
        _smardexToken = IERC20(smardexToken);
        _router = IUniversalRouter(router);
        _factory = ISmardexFactory(factory);
        _uniswapPair = uniswapPair;
        ZERO_FOR_ONE = _wstETH < _wETH;
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

    /// @inheritdoc IAutoSwapper
    function safeSwapSmarDex(uint256 wethAmount) external {
        if (msg.sender != address(this)) {
            revert AutoSwapperUnauthorized();
        }
        _swapSmarDex(wethAmount);
    }

    /**
     * @notice Executes a two-step swap: wstETH --> WETH --> SDEX.
     * @dev If the first swap fails, the second is skipped.
     * If the second swap fails, it is silently ignored.
     */
    function _processSwap() internal {
        uint256 wstEthAmount = _wstETH.balanceOf(address(this));
        if (wstEthAmount == 0) {
            revert AutoSwapperInvalidAmount();
        }

        try this.uniWstethToWeth(wstEthAmount) {
            uint256 wethAmount = _wETH.balanceOf(address(this));
            try this.safeSwapSmarDex(wethAmount) {
                emit SuccessfulSwap(wstEthAmount);
            } catch {
                emit FailedWEthSwap(wethAmount);
            }
        } catch {
            emit FailedWstEthSwap(wstEthAmount);
        }
    }

    function uniWstethToWeth(uint256 wstethAmount) external {
        (int256 amount0, int256 amount1) = IUniswapV3Pool(_uniswapPair).swap(
            address(this),
            ZERO_FOR_ONE,
            int256(wstethAmount),
            TickMath.getSqrtRatioAtTick(0),
            abi.encode(abi.encodePacked(_wstETH, _uniswapFeeTier, _wETH), msg.sender)
        );

        uint256 amountOut = uint256(-(ZERO_FOR_ONE ? amount1 : amount0));
        uint256 minAmountOut =
            IWstETH(address(_wstETH)).getStETHByWstETH(wstethAmount) * (BPS_DIVISOR - _swapSlippage) / BPS_DIVISOR;

        require(amountOut >= minAmountOut);
    }

    function uniswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata) external {
        require(msg.sender == _uniswapPair, "Caller is not the Uniswap V3 pool");
        require(amount0Delta > 0 || amount1Delta > 0);

        uint256 amountToPay = amount0Delta > 0 ? uint256(amount0Delta) : uint256(amount1Delta);

        _wstETH.transfer(msg.sender, amountToPay);
    }

    /**
     * @notice Swaps WETH for SDEX token using the SmarDex protocol
     * @dev Uses Permit2 for approvals, calculates minimum output with slippage protection
     * @param wethAmount Amount of WETH to swap
     */
    function _swapSmarDex(uint256 wethAmount) internal {
        SwapCallParams memory _params = SwapCallParams({
            balanceIn: wethAmount,
            pair: ISmardexPair(_factory.getPair(address(_wETH), address(_smardexToken))),
            fictiveReserve0: 0,
            fictiveReserve1: 0,
            oldPriceAv0: 0,
            oldPriceAv1: 0,
            oldPriceAvTimestamp: 0,
            newPriceAvIn: 0,
            newPriceAvOut: 0
        });

        // get reserves and pricesAv
        (_params.fictiveReserve0, _params.fictiveReserve1) = _params.pair.getFictiveReserves();
        (_params.oldPriceAv0, _params.oldPriceAv1, _params.oldPriceAvTimestamp) = _params.pair.getPriceAverage();

        (_params.newPriceAvIn, _params.newPriceAvOut) = SmardexLibrary.getUpdatedPriceAverage(
            _params.fictiveReserve1,
            _params.fictiveReserve0,
            _params.oldPriceAvTimestamp,
            _params.oldPriceAv1,
            _params.oldPriceAv0,
            block.timestamp
        );

        (uint256 reservesOut, uint256 reservesIn) = _params.pair.getReserves();

        SmardexLibrary.GetAmountParameters memory smardexParams = SmardexLibrary.GetAmountParameters({
            amount: wethAmount,
            reserveIn: reservesIn,
            reserveOut: reservesOut,
            fictiveReserveIn: _params.fictiveReserve1,
            fictiveReserveOut: _params.fictiveReserve0,
            priceAverageIn: _params.newPriceAvOut,
            priceAverageOut: _params.newPriceAvIn,
            feesLP: _smardexFeesLP,
            feesPool: _smardexFeesPool
        });

        (uint256 amountOut,,,,) = SmardexLibrary.getAmountOut(smardexParams);
        uint256 minAmountOut = amountOut * (BPS_DIVISOR - _swapSlippage) / BPS_DIVISOR;

        if (minAmountOut == 0) {
            revert AutoSwapperInvalidSlippageCalculation();
        }

        bytes memory commands = abi.encodePacked(SMARDEX_SWAP_EXACT_IN);
        bytes[] memory inputs = new bytes[](1);

        inputs[0] = abi.encode(
            BURN_ADDRESS, wethAmount, minAmountOut, abi.encodePacked(address(_wETH), address(_smardexToken)), true
        );

        _permit2Approve(_wETH, address(_router), wethAmount);
        _router.execute(commands, inputs);
    }

    /// @inheritdoc IAutoSwapper
    function swapTokenWithPath(uint256 amountToSwap, uint256 amountOutMin, address[] calldata path, uint8 command)
        external
        onlyOwner
    {
        if (path.length == 0) {
            revert AutoSwapperInvalidPath();
        }
        if (path[path.length - 1] != address(_smardexToken)) {
            revert AutoSwapperInvalidLastToken();
        }

        IERC20 inputToken = IERC20(path[0]);
        inputToken.transferFrom(msg.sender, address(this), amountToSwap);

        bytes memory commands = abi.encodePacked(command);
        bytes[] memory inputs = new bytes[](1);

        inputs[0] = abi.encode(BURN_ADDRESS, amountToSwap, amountOutMin, abi.encodePacked(path[0], path[1]), true);

        _permit2Approve(_wETH, address(_router), amountToSwap);
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

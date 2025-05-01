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
import { ISmardexRouter } from "@smardex-dex-contracts/contracts/ethereum/periphery/interfaces/ISmardexRouterV2.sol";
import { IUniversalRouter } from "@smardex-universal-router/src/interfaces/IUniversalRouter.sol";
import { IAllowanceTransfer } from "@uniswap/permit2/src/interfaces/IAllowanceTransfer.sol";
// to do : check this import
import { IUniswapV3Pool } from "@uniswapV3/contracts/interfaces/IUniswapV3Pool.sol";
import { FixedPoint96 } from "@uniswapV3/contracts/libraries/FixedPoint96.sol";
import { FullMath } from "@uniswapV3/contracts/libraries/FullMath.sol";
import { SqrtPriceMath } from "@uniswapV3/contracts/libraries/SqrtPriceMath.sol";
import { TickMath } from "@uniswapV3/contracts/libraries/TickMath.sol";

import { IWstETH } from "./../interfaces/IWstETH.sol";
import { IFeeCollectorCallback } from "./../interfaces/UsdnProtocol/IFeeCollectorCallback.sol";
import { IAutoSwapper } from "./../interfaces/Utils/IAutoSwapper.sol";

import { console } from "forge-std/Test.sol";

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

    /// @notice Time interval (in seconds) used for TWAP calculation.
    uint32 internal _twapInterval = 300; // 5 min

    // @todo think about short usdn and check if its compatible with wUSDN, if its possible look into

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
    function safeSwapV3(uint256 wstEthAmount) external {
        if (msg.sender != address(this)) {
            revert AutoSwapperUnauthorized();
        }
        _swapV3(wstEthAmount);
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

        try this.safeSwapV3(wstEthAmount) {
            uint256 wethAmount = _wETH.balanceOf(address(this));
            try this.safeSwapSmarDex(wethAmount) {
                emit SucessfullSwap(wstEthAmount);
            } catch {
                emit FailedWEthSwap(wethAmount);
            }
        } catch {
            emit FailedWstEthSwap(wstEthAmount);
        }
    }

    function exactInputSingle(uint256 wstethAmount) external {
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
     * @notice Swaps wstETH for WETH using Uniswap V3.
     * @dev Uses TWAP for price calculation with slippage protection.
     * @param wstEthAmount Amount of wstETH to swap.
     */
    function _swapV3(uint256 wstEthAmount) internal {
        uint256 expectedOutput = _getTwapAmountOut(_uniswapPair, uint128(wstEthAmount));
        uint256 minAmountOut = (expectedOutput * (BPS_DIVISOR - _swapSlippage)) / BPS_DIVISOR;

        bytes memory commands = abi.encodePacked(V3_SWAP_EXACT_IN);
        bytes memory path = abi.encodePacked(address(_wstETH), _uniswapFeeTier, address(_wETH));

        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(address(this), wstEthAmount, minAmountOut, path, true);

        _permit2Approve(_wstETH, address(_router), wstEthAmount);
        _router.execute(commands, inputs, block.timestamp);
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
     * @notice Calculates the TWAP-based output amount for a given input amount.
     * @param pool The address of the Uniswap V3 pool to query.
     * @param amountIn The input token amount.
     * @return amountOut_ The estimated output amount based on TWAP.
     */
    function _getTwapAmountOut(address pool, uint128 amountIn) internal view returns (uint256 amountOut_) {
        if (_twapInterval == 0) {
            revert AutoSwapperInvalidTwapInterval();
        }

        // Get tick cumulative values for current and past time
        uint32[] memory secondsAgos = new uint32[](2);
        secondsAgos[0] = _twapInterval;
        secondsAgos[1] = 0; // now

        (int56[] memory tickCumulatives,) = IUniswapV3Pool(pool).observe(secondsAgos);

        int56 tickDelta = tickCumulatives[1] - tickCumulatives[0];
        int24 averageTick = int24(tickDelta / int56(uint56(_twapInterval)));

        uint160 sqrtPriceX96 = TickMath.getSqrtRatioAtTick(averageTick);
        amountOut_ = _getQuoteAtSqrtPrice(amountIn, sqrtPriceX96);
    }

    /**
     * @notice Quotes the token output amount using a Uniswap sqrt price.
     * @param amountIn The input token amount.
     * @param sqrtPriceX96 The sqrt price as a Q64.96 fixed-point value.
     * @return The quoted output amount.
     */
    function _getQuoteAtSqrtPrice(uint256 amountIn, uint160 sqrtPriceX96) internal pure returns (uint256) {
        return FullMath.mulDiv(amountIn, sqrtPriceX96, FixedPoint96.Q96);
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
    function updateTwapInterval(uint32 newTwapInterval) external onlyOwner {
        if (newTwapInterval == 0) {
            revert AutoSwapperInvalidTwapInterval();
        }
        _twapInterval = newTwapInterval;
        emit TwapIntervalUpdated(newTwapInterval);
    }

    /// @inheritdoc IAutoSwapper
    function updateUniswapPair(address newPair) external onlyOwner {
        if (newPair == address(0)) {
            revert AutoSwapperInvalidPairAddress();
        }
        _uniswapPair = newPair;
        emit UniswapPairUpdated(newPair);
    }

    /// @inheritdoc IAutoSwapper
    function updateUniswapFeeTier(uint24 newFeeTier) external onlyOwner {
        if (newFeeTier == 0) {
            revert AutoSwapperInvalidUniswapFee();
        }
        _uniswapFeeTier = newFeeTier;
        emit UniswapFeeTierUpdated(newFeeTier);
    }

    /// @inheritdoc IAutoSwapper
    function updateSwapSlippage(uint256 newSwapSlippage) external onlyOwner {
        if (newSwapSlippage == 0) {
            revert AutoSwapperInvalidSwapSlippage();
        }
        _swapSlippage = newSwapSlippage;
        emit SwapSlippageUpdated(newSwapSlippage);
    }

    /// @inheritdoc IAutoSwapper
    function updateSmardexFeesLP(uint128 newFeesLP) external onlyOwner {
        if (newFeesLP + _smardexFeesPool >= SmardexLibrary.FEES_MAX) {
            revert AutoSwapperFeesExceedMaximum();
        }
        _smardexFeesLP = newFeesLP;
        emit SmardexFeesLPUpdated(newFeesLP);
    }

    /// @inheritdoc IAutoSwapper
    function updateSmardexFeesPool(uint128 newFeesPool) external onlyOwner {
        if (newFeesPool + _smardexFeesPool >= SmardexLibrary.FEES_MAX) {
            revert AutoSwapperFeesExceedMaximum();
        }
        _smardexFeesPool = newFeesPool;
        emit SmardexFeesPoolUpdated(newFeesPool);
    }
}

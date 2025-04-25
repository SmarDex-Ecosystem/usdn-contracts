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

import { IUniswapV3Pool } from "@uniswapV3/contracts/interfaces/IUniswapV3Pool.sol";
import { FixedPoint96 } from "@uniswapV3/contracts/libraries/FixedPoint96.sol";
import { FullMath } from "@uniswapV3/contracts/libraries/FullMath.sol";
import { SqrtPriceMath } from "@uniswapV3/contracts/libraries/SqrtPriceMath.sol";
import { TickMath } from "@uniswapV3/contracts/libraries/TickMath.sol";

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

    /// @notice Base denominator for slippage calculation (e.g., 100 = 100%).
    uint256 private constant AUTOSWAP_SLIPPAGE_BASE = 100;

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

    /* -------------------------------------------------------------------------- */
    /*                          Admin Configurable Params                         */
    /* -------------------------------------------------------------------------- */

    /// @notice Uniswap V3 pool used for wstETH → WETH swap.
    address internal _uniswapPair;

    /// @notice Allowed slippage percentage for Uniswap V3 swaps.
    uint256 internal _swapSlippage = 2; // 2%

    /// @notice Fee tier used for Uniswap V3 path.
    uint24 internal _uniswapFeeTier = 100; // 0.01% fee tier

    /// @notice Time interval (in seconds) used for TWAP calculation.
    uint32 internal _twapInterval = 300; // 5 min

    // @todo think about short usdn and check if its compatible with wUSDN, if its possible look into
    // @todo add into consideration mev manipulation and sandwich attach and check for security related to balance
    // stored in contract
    // @todo add functionality to make generic or admin to chose any path to handle more coins

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
    }

    /// @inheritdoc ERC165
    function supportsInterface(bytes4 interfaceId) public view override(ERC165, IERC165) returns (bool) {
        if (interfaceId == type(IFeeCollectorCallback).interfaceId) {
            return true;
        }
        return super.supportsInterface(interfaceId);
    }

    /// @inheritdoc IFeeCollectorCallback
    function feeCollectorCallback(uint256 _amount) external override nonReentrant {
        if (_amount == 0) {
            revert AutoSwapperInvalidAmount();
        }
        _processSwap(_amount);
    }

    /// @inheritdoc IAutoSwapper
    function safeSwapV3(uint256 amount) external {
        if (msg.sender != address(this)) {
            revert AutoSwapperUnauthorized();
        }
        _swapV3(amount);
    }

    /// @inheritdoc IAutoSwapper
    function safeSwapSmarDex() external {
        if (msg.sender != address(this)) {
            revert AutoSwapperUnauthorized();
        }
        _swapSmarDex();
    }

    /**
     * @notice Executes a two-step swap: wstETH → WETH → SDEX.
     * @dev If the first swap fails, the second is skipped.
     * If the second swap fails, it is silently ignored.
     * @param _amount Amount of wstETH to process.
     */
    function _processSwap(uint256 _amount) internal {
        try this.safeSwapV3(_amount) {
            uint256 wethAmount = _wETH.balanceOf(address(this));
            try this.safeSwapSmarDex() {
                emit SucessfullSwap(_amount);
            } catch {
                emit FailedWEthSwap(wethAmount);
            }
        } catch {
            emit FailedWstEthSwap(_amount);
        }
    }

    /**
     * @notice Swaps wstETH for WETH using Uniswap V3.
     * @dev Uses TWAP for price calculation with slippage protection.
     * @param _amount Amount of wstETH to swap.
     */
    function _swapV3(uint256 _amount) internal {
        uint256 expectedOutput = _getTwapAmountOut(_uniswapPair, uint128(_amount));
        uint256 minAmountOut = (expectedOutput * (AUTOSWAP_SLIPPAGE_BASE - _swapSlippage)) / AUTOSWAP_SLIPPAGE_BASE;

        bytes memory commands = abi.encodePacked(V3_SWAP_EXACT_IN);
        bytes memory path = abi.encodePacked(address(_wstETH), _uniswapFeeTier, address(_wETH));

        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(address(this), _amount, minAmountOut, path, true);

        _permit2Approve(_wstETH, address(_router), _amount);
        _router.execute(commands, inputs, block.timestamp);
    }

    /**
     * @notice Swaps all WETH held by the contract into SDEX using the SmarDex router.
     * @dev Transfers WETH to the router and performs an exact input swap to SDEX.
     */
    function _swapSmarDex() internal {
        uint256 wETHbalance = _wETH.balanceOf(address(this));
        SwapCallParams memory _params = SwapCallParams({
            zeroForOne: _wETH < _smardexToken,
            balanceIn: wETHbalance,
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

        SmardexLibrary.GetAmountParameters memory testParam = SmardexLibrary.GetAmountParameters({
            amount: wETHbalance,
            reserveIn: reservesIn,
            reserveOut: reservesOut,
            fictiveReserveIn: _params.fictiveReserve1,
            fictiveReserveOut: _params.fictiveReserve0,
            priceAverageIn: _params.newPriceAvOut,
            priceAverageOut: _params.newPriceAvIn,
            feesLP: 5,
            feesPool: 2
        });

        (uint256 amountOut,,,,) = SmardexLibrary.getAmountOut(testParam);
        uint256 minAmountOut = amountOut * (AUTOSWAP_SLIPPAGE_BASE - _swapSlippage) / AUTOSWAP_SLIPPAGE_BASE;

        if (minAmountOut == 0) {
            revert AutoSwapperInvalidSlippageCalculation();
        }

        bytes memory commands = abi.encodePacked(SMARDEX_SWAP_EXACT_IN);
        bytes[] memory inputs = new bytes[](1);

        inputs[0] = abi.encode(
            BURN_ADDRESS, wETHbalance, minAmountOut, abi.encodePacked(address(_wETH), address(_smardexToken)), true
        );

        _permit2Approve(_wETH, address(_router), wETHbalance);
        _router.execute(commands, inputs);
    }

    /// @inheritdoc IAutoSwapper
    function swapTokenWithPath(uint256 _amountToSwap, uint256 _amountOutMin, address[] calldata _path, uint8 _command)
        external
        onlyOwner
    {
        if (_path.length == 0) {
            revert AutoSwapperInvalidPath();
        }
        if (_path[_path.length - 1] != address(_smardexToken)) {
            revert AutoSwapperInvalidLastToken();
        }

        IERC20 inputToken = IERC20(_path[0]);
        inputToken.transferFrom(msg.sender, address(this), _amountToSwap);

        bytes memory commands = abi.encodePacked(_command);
        bytes[] memory inputs = new bytes[](1);

        inputs[0] = abi.encode(BURN_ADDRESS, _amountToSwap, _amountOutMin, abi.encodePacked(_path[0], _path[1]), true);

        _permit2Approve(_wETH, address(_router), _amountToSwap);
        _router.execute(commands, inputs);
    }

    /**
     * @notice Calculates the TWAP-based output amount for a given input amount.
     * @param _pool The address of the Uniswap V3 pool to query.
     * @param _amountIn The input token amount.
     * @return amountOut The estimated output amount based on TWAP.
     */
    function _getTwapAmountOut(address _pool, uint128 _amountIn) internal view returns (uint256 amountOut) {
        if (_twapInterval == 0) {
            revert AutoSwapperInvalidTwapInterval();
        }

        // Get tick cumulative values for current and past time
        uint32[] memory secondsAgos = new uint32[](2);
        secondsAgos[0] = _twapInterval;
        secondsAgos[1] = 0; // now

        (int56[] memory tickCumulatives,) = IUniswapV3Pool(_pool).observe(secondsAgos);

        int56 tickDelta = tickCumulatives[1] - tickCumulatives[0];
        int24 averageTick = int24(tickDelta / int56(uint56(_twapInterval)));

        uint160 sqrtPriceX96 = TickMath.getSqrtRatioAtTick(averageTick);
        amountOut = _getQuoteAtSqrtPrice(_amountIn, sqrtPriceX96);
    }

    /**
     * @notice Quotes the token output amount using a Uniswap sqrt price.
     * @param _amountIn The input token amount.
     * @param _sqrtPriceX96 The sqrt price as a Q64.96 fixed-point value.
     * @return The quoted output amount.
     */
    function _getQuoteAtSqrtPrice(uint256 _amountIn, uint160 _sqrtPriceX96) internal pure returns (uint256) {
        return FullMath.mulDiv(_amountIn, _sqrtPriceX96, FixedPoint96.Q96);
    }

    // @todo check if we can approve max once through admin?
    /**
     * @notice Approves the Permit2 contract to transfer tokens and grants Permit2 approval to a spender.
     * @dev Uses SafeCast to ensure proper type conversion for Permit2.
     * @param _token The ERC20 token to approve.
     * @param _spender The address to be approved to spend tokens via Permit2.
     * @param _approveAmount The amount of tokens to approve.
     */
    function _permit2Approve(IERC20 _token, address _spender, uint256 _approveAmount) internal {
        _token.approve(address(PERMIT2), _approveAmount);
        PERMIT2.approve(address(_token), address(_spender), uint160(_approveAmount), uint48(block.timestamp));
    }

    /// @inheritdoc IAutoSwapper
    function updateTwapInterval(uint32 _newTwapInterval) external onlyOwner {
        if (_newTwapInterval == 0) {
            revert AutoSwapperInvalidTwapInterval();
        }
        _twapInterval = _newTwapInterval;
        emit TwapIntervalUpdated(_newTwapInterval);
    }

    /// @inheritdoc IAutoSwapper
    function updateUniswapPair(address _newPair) external onlyOwner {
        if (_newPair == address(0)) {
            revert AutoSwapperInvalidPairAddress();
        }
        _uniswapPair = _newPair;
        emit UniswapPairUpdated(_newPair);
    }

    /// @inheritdoc IAutoSwapper
    function updateUniswapFeeTier(uint24 _newFeeTier) external onlyOwner {
        if (_newFeeTier == 0) {
            revert AutoSwapperInvalidUniswapFee();
        }
        _uniswapFeeTier = _newFeeTier;
        emit UniswapFeeTierUpdated(_newFeeTier);
    }

    /// @inheritdoc IAutoSwapper
    function updateSwapSlippage(uint256 _newSwapSlippage) external onlyOwner {
        if (_newSwapSlippage == 0) {
            revert AutoSwapperInvalidSwapSlippage();
        }
        _swapSlippage = _newSwapSlippage;
        emit SwapSlippageUpdated(_newSwapSlippage);
    }
}

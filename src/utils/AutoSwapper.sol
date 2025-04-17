// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import { Test, console } from "forge-std/Test.sol";

import { Ownable, Ownable2Step } from "@openzeppelin/contracts/access/Ownable2Step.sol";
import { IERC20, SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ERC165 } from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import { IERC165 } from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { IUniversalRouter } from "@smardex-universal-router-1.0.0/src/interfaces/IUniversalRouter.sol";

import { FullMath } from "@uniswapV3//contracts/libraries/FullMath.sol";
import { IUniswapV3Pool } from "@uniswapV3/contracts/interfaces/IUniswapV3Pool.sol";
import { FixedPoint96 } from "@uniswapV3/contracts/libraries/FixedPoint96.sol";
import { SqrtPriceMath } from "@uniswapV3/contracts/libraries/SqrtPriceMath.sol";
import { TickMath } from "@uniswapV3/contracts/libraries/TickMath.sol";

import { IFeeCollectorCallback } from "./../interfaces/UsdnProtocol/IFeeCollectorCallback.sol";
import { IAutoSwapper } from "./../interfaces/Utils/IAutoSwapper.sol";

/**
 * @title AutoSwapper
 * @notice Automates protocol fee conversion from wstETH to SDEX via Uniswap V3 and Smardex.
 */
contract AutoSwapper is Ownable2Step, IAutoSwapper, IFeeCollectorCallback, ERC165 {
    using SafeERC20 for IERC20;
    using SafeCast for uint256;
    using SafeCast for int256;
    // using Path for bytes;
    // using Path for address[];

    /* -------------------------------------------------------------------------- */
    /*                                  Constants                                 */
    /* -------------------------------------------------------------------------- */

    /// @notice Base denominator for slippage calculation (e.g., 100 = 100%)
    uint256 private constant AUTOSWAP_SLIPPAGE_BASE = 100;

    /// @notice Uniswap V3 command code for exact input swap
    uint8 private constant V3_SWAP_EXACT_IN = 0x00;

    /// @notice SmarDex command code for exact input swap
    uint8 private constant SMARDEX_SWAP_EXACT_IN = 0x38;

    /// @notice Reserved sweep command
    uint8 private constant SWEEP = 0x04; // @todo check if we can use it

    /// @notice Burn address for receiving output tokens
    address internal constant BURN_ADDRESS = 0x000000000000000000000000000000000000dEaD;

    /* -------------------------------------------------------------------------- */
    /*                                 Immutables                                 */
    /* -------------------------------------------------------------------------- */

    /// @notice Wrapped staked ETH token used as input for swaps
    IERC20 internal immutable wstETH;

    /// @notice Wrapped ETH token received from Uniswap V3 swaps
    IERC20 internal immutable wETH;

    /// @notice Final output token after SmarDex swap
    IERC20 internal immutable smardexToken;

    /// @notice Uniswap V3 pool used for wstETH → WETH swap
    address internal uniswapPair = 0x109830a1AAaD605BbF02a9dFA7B0B92EC2FB7dAa;

    /// @notice Allowed slippage percentage for Uniswap V3 swaps
    uint256 internal swapSlippage = 2; // 2%

    /// @notice Fee tier used for Uniswap V3 path
    uint24 internal uniswapFeeTier = 100; // 0.01% fee tier

    /// @notice Time interval (in seconds) used for TWAP calculation
    uint32 internal twapInterval = 300; // 5 min

    // ISmardexPair private constant DEFAULT_CACHED_PAIR = ISmardexPair(address(0));
    // ISmardexPair private cachedPair = DEFAULT_CACHED_PAIR;

    // @todo think about short usdn and check if its compatible with wUSDN, if its possible look into
    // @todo add into consideration mev manipulation and sandwich attach and check for security related to balance
    // stored in contract
    // @todo add functionality to make generic or admin to chose any path to handle more coins
    /// @notice Universal Router instance for performing multi-hop swaps
    IUniversalRouter internal immutable router;

    /**
     * @notice Constructs the AutoSwapper contract
     * @param _wstETH Address of the wstETH token
     * @param _wETH Address of the WETH token
     * @param _smardexToken Address of the SDEX token
     * @param _router Address of the Universal Router
     */
    constructor(address _wstETH, address _wETH, address _smardexToken, address _router) Ownable(msg.sender) {
        if (_wstETH == address(0)) revert InvalidWstETHAddress();
        if (_wETH == address(0)) revert InvalidWETHAddress();
        if (_smardexToken == address(0)) revert InvalidSDEXAddress();
        if (_router == address(0)) revert InvalidRouterAddress();

        wstETH = IERC20(_wstETH);
        wETH = IERC20(_wETH);
        smardexToken = IERC20(_smardexToken);
        router = IUniversalRouter(_router);

        wstETH.approve(address(router), type(uint256).max);
    }

    /// @inheritdoc ERC165
    function supportsInterface(bytes4 interfaceId) public view override(ERC165, IERC165) returns (bool) {
        if (interfaceId == type(IFeeCollectorCallback).interfaceId) {
            return true;
        }
        return super.supportsInterface(interfaceId);
    }

    /// @inheritdoc IFeeCollectorCallback
    function feeCollectorCallback(uint256 _amount) external override {
        if (_amount == 0) {
            revert InvalidAmount();
        }
        processSwap(_amount);
    }

    /// @inheritdoc IAutoSwapper
    function processSwap(uint256 _amount) public {
        try this.safeSwapV3(_amount) {
            uint256 wethAmount = wETH.balanceOf(address(this));
            try this.safeSwapSmarDex() {
                emit sucessfullSwap(_amount);
            } catch {
                emit failedWEthSwap(wethAmount);
            }
        } catch {
            emit failedWstEthSwap(_amount);
        }
    }

    /// @inheritdoc IAutoSwapper
    function safeSwapV3(uint256 amount) external {
        _swapV3(amount);
    }

    /// @inheritdoc IAutoSwapper
    function safeSwapSmarDex() external {
        _swapSmarDex();
    }

    /**
     * @notice Swaps wstETH for WETH using Uniswap V3
     * @dev Uses TWAP for price calculation with slippage protection
     * @param _amount Amount of wstETH to swap
     */
    function _swapV3(uint256 _amount) internal {
        uint256 expectedOutput = _getTwapAmountOut(uniswapPair, uint128(_amount));
        uint256 minAmountOut = (expectedOutput * (AUTOSWAP_SLIPPAGE_BASE - swapSlippage)) / AUTOSWAP_SLIPPAGE_BASE;

        bytes memory commands = abi.encodePacked(V3_SWAP_EXACT_IN);
        bytes memory path = abi.encodePacked(address(wstETH), uniswapFeeTier, address(wETH));

        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(address(this), _amount, minAmountOut, path, false);

        router.execute(commands, inputs, block.timestamp);
    }

    /**
     * @notice Swaps all WETH held by the contract into SDEX using the SmarDex router.
     * @dev Transfers WETH to the router and performs an exact input swap to SDEX.
     */
    function _swapSmarDex() internal {
        console.log("WETH balance before swap:", wETH.balanceOf(address(this)));

        uint256 wETHbalance = wETH.balanceOf(address(this));
        wETH.transfer(address(router), wETHbalance);

        console.log("WETH balance rputer:", wETH.balanceOf(address(router)));

        bytes memory commands = abi.encodePacked(SMARDEX_SWAP_EXACT_IN);
        bytes[] memory inputs = new bytes[](1);

        inputs[0] = abi.encode(
            BURN_ADDRESS,
            wETHbalance,
            0, // Minimum amount out (no slippage protection)
            abi.encodePacked(address(wETH), address(smardexToken)),
            false
        );

        router.execute(commands, inputs);
    }

    /// @inheritdoc IAutoSwapper
    function swapTokenWithPath(uint256 _amountToSwap, uint256 _amountOutMin, address[] calldata _path, uint8 _command)
        external
        onlyOwner
    {
        if (_path.length == 0) {
            revert InvalidPath();
        }
        if (_path[_path.length - 1] != address(smardexToken)) {
            revert InvalidLastToken();
        }

        // @todo verify permit2 will send funds directly and more gas efficient
        // uint256 blockTimestamp = block.timestamp;
        // permit2.approve(wETHAddress, address(router), type(uint160).max, uint48(blockTimestamp));

        bytes memory commands = abi.encodePacked(_command);
        bytes[] memory inputs = new bytes[](1);

        // true: balance of swapper
        // false: balance of router
        inputs[0] = abi.encode(BURN_ADDRESS, _amountToSwap, _amountOutMin, abi.encodePacked(_path[0], _path[1]), false);

        router.execute(commands, inputs);
    }

    /**
     * @notice Calculates the TWAP-based output amount for a given input amount.
     * @param pool The address of the Uniswap V3 pool to query.
     * @param amountIn The input token amount.
     * @return amountOut The estimated output amount based on TWAP.
     */
    function _getTwapAmountOut(address pool, uint128 amountIn) internal view returns (uint256 amountOut) {
        if (twapInterval == 0) {
            revert InvalidTwapInterval();
        }

        // Get tick cumulative values for current and past time
        uint32[] memory secondsAgos = new uint32[](2);
        secondsAgos[0] = twapInterval;
        secondsAgos[1] = 0; // now

        (int56[] memory tickCumulatives,) = IUniswapV3Pool(pool).observe(secondsAgos);

        int56 tickDelta = tickCumulatives[1] - tickCumulatives[0];
        int24 averageTick = int24(tickDelta / int56(uint56(twapInterval)));

        uint160 sqrtPriceX96 = TickMath.getSqrtRatioAtTick(averageTick);
        amountOut = _getQuoteAtSqrtPrice(amountIn, sqrtPriceX96);
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

    /// @inheritdoc IAutoSwapper
    function updateTwapInterval(uint32 _newTwapInterval) external onlyOwner {
        if (_newTwapInterval == 0) {
            revert InvalidTwapInterval();
        }
        twapInterval = _newTwapInterval;
    }

    /// @inheritdoc IAutoSwapper
    function updateUniswapPair(address _newPair) external onlyOwner {
        if (_newPair == address(0)) {
            revert InvalidPairAddress();
        }
        uniswapPair = _newPair;
    }

    /// @inheritdoc IAutoSwapper
    function updateUniswapFeeTier(uint24 _feeTier) external onlyOwner {
        if (_feeTier == 0) {
            revert InvalidUniswapFee();
        }
        uniswapFeeTier = _feeTier;
    }

    /// @inheritdoc IAutoSwapper
    function updateSwapSlippage(uint256 _swapSlippage) external onlyOwner {
        if (_swapSlippage == 0) {
            revert InvalidSwapSlippage();
        }
        swapSlippage = _swapSlippage;
    }

    // @todo should this contract receive eth?
    receive() external payable { }
}

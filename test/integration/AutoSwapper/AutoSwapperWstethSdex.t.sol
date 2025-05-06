// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.27;

import { Test } from "forge-std/Test.sol";

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { SDEX as SDEX_ADDR, WETH as WETH_ADDR, WSTETH as WSTETH_ADDR } from "../../utils/Constants.sol";

import { IAutoSwapperWstethSdex } from "../../../src/interfaces/Utils/IAutoSwapperWstethSdex.sol";
import { AutoSwapperWstethSdex } from "../../../src/utils/AutoSwapperWstethSdex.sol";

/**
 * @custom:feature The `AutoSwapperWstethSdex` contract
 * @custom:background Given a `AutoSwapperWstethSdex` contract and a forked mainnet
 */
contract TestForkAutoSwapperWstethSdex is Test {
    AutoSwapperWstethSdex public autoSwapper;

    address constant BURN_ADDRESS = 0x000000000000000000000000000000000000dEaD;
    address constant USDN_PROTOCOL = 0x656cB8C6d154Aad29d8771384089be5B5141f01a;
    IERC20 constant SDEX = IERC20(SDEX_ADDR);
    IERC20 constant WETH = IERC20(WETH_ADDR);
    IERC20 constant WSTETH = IERC20(WSTETH_ADDR);

    function setUp() public {
        vm.createSelectFork("mainnet");

        autoSwapper = new AutoSwapperWstethSdex();

        deal(address(WSTETH), USDN_PROTOCOL, 100 ether);
    }

    /**
     * @custom:scenario Test the AutoSwapper's full swap execution via the callback function
     * @custom:when `feeCollectorCallback` is called
     * @custom:then It should perform both swaps
     * @custom:and the SDEX balance of the burn address should increase
     * @custom:and the wstETH and WETH balances of the contract should be zero
     */
    function test_ForkFeeCollectorCallback() public {
        uint256 amountToSwap = 1 ether;
        uint256 initialBurnAddressBalance = SDEX.balanceOf(BURN_ADDRESS);

        vm.startPrank(USDN_PROTOCOL);
        WSTETH.transfer(address(autoSwapper), amountToSwap);
        autoSwapper.feeCollectorCallback(1);
        vm.stopPrank();

        assertEq(WSTETH.balanceOf(address(autoSwapper)), 0, "wstETH balance not zero");
        assertEq(WETH.balanceOf(address(autoSwapper)), 0, "WETH balance not zero");
        assertEq(SDEX.balanceOf(address(autoSwapper)), 0, "SDEX balance not zero");
        assertGt(
            SDEX.balanceOf(BURN_ADDRESS), initialBurnAddressBalance, "Swap did not increase burn address SDEX balance"
        );
    }

    /**
     * @custom:scenario Test the `Ownable` access control of the AutoSwapper
     * @custom:when the `sweep` and `updateSwapSlippage` functions are called
     * @custom:then It should revert with the `OwnableUnauthorizedAccount` error
     */
    function test_ForkAdmin() public {
        address user = vm.addr(1);
        vm.startPrank(user);

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user));
        autoSwapper.sweep(address(0), address(0), 1);

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user));
        autoSwapper.updateSwapSlippage(1);

        vm.stopPrank();
    }

    /**
     * @custom:scenario Test the external function calls of the AutoSwapper
     * @custom:when the `uniswapV3SwapCallback` and `smardexSwapCallback` functions are called
     * @custom:then it should revert with the `AutoSwapperInvalidCaller` error
     */
    function test_ForkInvalidCaller() public {
        address user = vm.addr(1);
        vm.startPrank(user);

        vm.expectRevert(IAutoSwapperWstethSdex.AutoSwapperInvalidCaller.selector);
        autoSwapper.uniswapV3SwapCallback(1, 1, "");

        vm.expectRevert(IAutoSwapperWstethSdex.AutoSwapperInvalidCaller.selector);
        autoSwapper.smardexSwapCallback(1, 1, "");

        vm.stopPrank();
    }
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.27;

import { Test } from "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { IAutoSwapperWstethSdex } from "../../../src/interfaces/Utils/IAutoSwapperWstethSdex.sol";
import { AutoSwapperWstethSdex } from "../../../src/utils/AutoSwapperWstethSdex.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @custom:feature The callback function of the `AutoSwapperWstethSdex` contract
 * @custom:background Given a `AutoSwapperWstethSdex` contract
 */
contract TestAutoSwapperWstethSdex is Test {
    AutoSwapperWstethSdex public swapper;

    IERC20 public wstETH;
    IERC20 public wETH;
    IERC20 public sDEX;

    address BURN_ADDRESS = 0x000000000000000000000000000000000000dEaD;
    address constant USDN_PROTOCOL = 0x656cB8C6d154Aad29d8771384089be5B5141f01a;

    function setUp() public {
        vm.createSelectFork("mainnet");

        wstETH = IERC20(0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0);
        wETH = IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
        sDEX = IERC20(0x5DE8ab7E27f6E7A1fFf3E5B337584Aa43961BEeF);

        swapper = new AutoSwapperWstethSdex();

        deal(address(wstETH), USDN_PROTOCOL, 100 ether);
    }

    /**
     * @custom:scenario Test the AutoSwapper's full swap execution via the callback function
     * @custom:when `feeCollectorCallback` is called
     * @custom:then It should perform both swaps
     * @custom:and the SDEX balance of the burn address should increase
     * @custom:and the wstETH and WETH balances of the contract should be zero
     */
    function test_feeCollectorCallback() public {
        uint256 amountToSwap = 1 ether;
        uint256 initialBurnAddressBalance = sDEX.balanceOf(BURN_ADDRESS);

        vm.startPrank(USDN_PROTOCOL);
        wstETH.transfer(address(swapper), amountToSwap);
        swapper.feeCollectorCallback(1);
        vm.stopPrank();

        assertGt(
            sDEX.balanceOf(BURN_ADDRESS), initialBurnAddressBalance, "Swap did not increase burn address SDEX balance"
        );
        assertEq(wstETH.balanceOf(address(swapper)), 0, "wstETH balance not zero");
        assertEq(wETH.balanceOf(address(swapper)), 0, "WETH balance not zero");
    }

    /**
     * @custom:scenario Test the `Ownable` access control of the AutoSwapper
     * @custom:when the `sweep`, `forceSwap`, and `updateSwapSlippage` functions are called
     * @custom:then It should revert with the `OwnableUnauthorizedAccount` error
     */
    function test_admin() public {
        address user = vm.addr(1);
        vm.startPrank(user);

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user));
        swapper.sweep(address(0), address(0), 1);

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user));
        swapper.forceSwap();

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user));
        swapper.updateSwapSlippage(1);

        vm.stopPrank();
    }

    /**
     * @custom:scenario Test the external function calls of the AutoSwapper
     * @custom:when the `uniWstethToWeth`, `uniswapV3SwapCallback`, `smarDexWethToSdex`, and `smardexSwapCallback`
     * functions are called
     * @custom:then it should revert with the `AutoSwapperInvalidCaller` error
     * @custom:and the `feeCollectorCallback` function should revert with the same error
     */
    function test_invalidCaller() public {
        address user = vm.addr(1);
        vm.startPrank(user);

        vm.expectRevert(IAutoSwapperWstethSdex.AutoSwapperInvalidCaller.selector);
        swapper.feeCollectorCallback(1);

        vm.expectRevert(IAutoSwapperWstethSdex.AutoSwapperInvalidCaller.selector);
        swapper.uniWstethToWeth();

        vm.expectRevert(IAutoSwapperWstethSdex.AutoSwapperInvalidCaller.selector);
        swapper.uniswapV3SwapCallback(1, 1, "");

        vm.expectRevert(IAutoSwapperWstethSdex.AutoSwapperInvalidCaller.selector);
        swapper.smarDexWethToSdex();

        vm.expectRevert(IAutoSwapperWstethSdex.AutoSwapperInvalidCaller.selector);
        swapper.smardexSwapCallback(1, 1, "");

        vm.stopPrank();
    }
}

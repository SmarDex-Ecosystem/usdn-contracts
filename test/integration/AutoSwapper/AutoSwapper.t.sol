// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { Test, console } from "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IUniversalRouter } from "@smardex-universal-router-1.0.0/src/interfaces/IUniversalRouter.sol";
import { IAllowanceTransfer } from "@uniswap/permit2/src/interfaces/IAllowanceTransfer.sol";

import { IAutoSwapper } from "../../../src/interfaces/Utils/IAutoSwapper.sol";
import { AutoSwapper } from "../../../src/utils/AutoSwapper.sol";

/**
 * @custom:feature The callback function of the `FeeCollector` contract
 * @custom:background Given a `FeeCollector` contract
 */
contract TestAutoSwapper is Test {
    IUniversalRouter public router;
    AutoSwapper public swapper;

    IERC20 public wstETH;
    IERC20 public wETH;
    IERC20 public sDEX;

    address user;
    address wETHAddress = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address wstETHAddress = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
    address sDEXAddress = 0x5DE8ab7E27f6E7A1fFf3E5B337584Aa43961BEeF;
    address routerAddress = 0x49f66B1616865b2a59caECb8352bbf2AC80983e1;
    address BURN_ADDRESS = 0x000000000000000000000000000000000000dEaD;

    function setUp() public {
        vm.createSelectFork("https://ethereum.publicnode.com/", 22_266_619);

        user = makeAddr("user_one");

        router = IUniversalRouter(routerAddress);
        wstETH = IERC20(wstETHAddress);
        wETH = IERC20(wETHAddress);
        sDEX = IERC20(sDEXAddress);

        vm.prank(user);
        swapper = new AutoSwapper(wstETHAddress, wETHAddress, sDEXAddress, routerAddress);

        vm.startPrank(address(swapper));
        wstETH.approve(address(router), type(uint256).max);
        wETH.approve(address(router), type(uint256).max);
        vm.stopPrank();

        vm.prank(user);
        wETH.approve(address(router), type(uint256).max);

        vm.prank(user);
        wETH.approve(address(swapper), type(uint256).max);

        deal(address(wstETH), user, 100 ether);
        deal(address(wETH), user, 100 ether);
    }

    // function test_swapTokenWithPath2() public {
    //     IAllowanceTransfer permit2 = IAllowanceTransfer(0x000000000022D473030F116dDEE9F6B43aC78BA3);

    //     // Set approvals from the user's context
    //     vm.startPrank(user);

    //     console.log("user", user);
    //     console.log("router", address(router));

    //     // User approves Permit2 to spend their WETH
    //     IERC20(wETHAddress).approve(address(permit2), type(uint256).max);

    //     uint256 blockTimestamp = block.timestamp + 1000;

    //     // User grants allowance to the router through Permit2
    //     permit2.approve(wETHAddress, address(router), type(uint160).max, uint48(blockTimestamp));

    //     // Prepare path
    //     address[] memory path = new address[](2);
    //     path[0] = wETHAddress;
    //     path[1] = sDEXAddress;

    //     // Call swap function (still as user)
    //     swapper.swapTokenWithPath(1 ether, 0, path, 0x38);

    //     vm.stopPrank();
    // }

    /**
     * @custom:scenario Test the AutoSwapper's full swap execution via processSwap
     * @custom:given The contract holds wstETH and is configured correctly
     * @custom:when processSwap is called with a valid amount
     * @custom:then It should perform both swaps and emit the `sucessfullSwap` event
     */
    function test_processSwap_emitsEventAndBurnsTokens() public {
        uint256 amountToSwap = 10 ether;
        uint256 initialBurnAddressBalance = IERC20(sDEXAddress).balanceOf(BURN_ADDRESS);

        vm.prank(user);
        wstETH.transfer(address(router), amountToSwap);

        //Expect the success event
        vm.expectEmit(true, false, false, true);
        emit IAutoSwapper.sucessfullSwap(amountToSwap);

        vm.prank(address(this));
        swapper.processSwap(amountToSwap);

        uint256 finalBurnAddressBalance = IERC20(sDEXAddress).balanceOf(BURN_ADDRESS);
        assertGt(finalBurnAddressBalance, initialBurnAddressBalance, "Swap did not increase burn address SDEX balance");
    }

    /**
     * @custom:scenario Test the owner's ability to swap tokens via the swapTokenWithPath function
     * @custom:given The owner has WETH tokens and wants to swap them for SDEX
     * @custom:when The owner transfers WETH to the router and calls swapTokenWithPath with the correct path
     * @custom:then The swap should execute successfully and route the tokens through SmarDex
     */
    function test_swapTokenWithPath() public {
        uint256 initialBurnAddressBalance = IERC20(sDEXAddress).balanceOf(BURN_ADDRESS);

        vm.startPrank(user);

        wETH.transfer(address(router), 1 ether);

        // Prepare path
        address[] memory path = new address[](2);
        path[0] = wETHAddress;
        path[1] = sDEXAddress;

        swapper.swapTokenWithPath(1 ether, 0, path, 0x38);

        vm.stopPrank();

        uint256 finalBurnAddressBalance = IERC20(sDEXAddress).balanceOf(BURN_ADDRESS);
        assertGt(finalBurnAddressBalance, initialBurnAddressBalance, "Swap did not increase burn address SDEX balance");
    }
}

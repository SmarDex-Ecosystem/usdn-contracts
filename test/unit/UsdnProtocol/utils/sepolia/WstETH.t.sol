// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { Test } from "forge-std/Test.sol";

import { StETH } from "../../../../../src/utils/sepolia/tokens/StETH.sol";
import { WstETH } from "../../../../../src/utils/sepolia/tokens/WstETH.sol";

contract TestSepoliaWstETH is Test {
    WstETH internal wstETH;
    StETH internal stETH;

    function setUp() public {
        stETH = new StETH();
        wstETH = new WstETH(stETH);
        wstETH.setStEthPerToken(1.2 ether);
    }

    function test_tokensPerStEth() public {
        assertEq(wstETH.tokensPerStEth(), 833_333_333_333_333_333);

        wstETH.setStEthPerToken(2 ether);
        assertEq(wstETH.tokensPerStEth(), 0.5 ether);
    }

    function test_getStETHByWstETH() public {
        assertEq(wstETH.getStETHByWstETH(1 ether), 1.2 ether);

        wstETH.setStEthPerToken(0.5 ether);
        assertEq(wstETH.getStETHByWstETH(2 ether), 1 ether);
    }

    function test_getWstETHByStETH() public {
        assertEq(wstETH.getWstETHByStETH(1 ether), 833_333_333_333_333_333);

        wstETH.setStEthPerToken(2 ether);
        assertEq(wstETH.getWstETHByStETH(2 ether), 1 ether);
    }

    function test_mintWhenReceivingEther() public {
        uint256 ethAmount = 2 ether;
        (bool success,) = address(wstETH).call{ value: ethAmount }("");

        assertTrue(success);
        assertEq(wstETH.balanceOf(address(this)), 833_333_333_333_333_333 * 2);
    }

    function test_withdraw() public {
        uint256 ethAmount = 2 ether;
        (bool success,) = address(wstETH).call{ value: ethAmount }("");
        assertTrue(success);

        uint256 balanceBefore = address(this).balance;
        wstETH.withdraw(wstETH.balanceOf(address(this)));

        assertEq(wstETH.balanceOf(address(this)), 0);
        assertApproxEqAbs(balanceBefore + 2 ether, address(this).balance, 1);
    }

    receive() external payable { }
}

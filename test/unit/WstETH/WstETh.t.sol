// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { USER_1 } from "../../utils/Constants.sol";
import { WstEthFixture } from "./utils/Fixtures.sol";

/**
 * @custom:feature Test functions in `wstEth`
 */
contract TestWstEth is WstEthFixture {
    function setUp() public override {
        super.setUp();
        deal(USER_1, 1 ether);
        stETH.mint(USER_1, 1 ether);
    }

    function test_wrap() public {
        assertEq(stETH.balanceOf(USER_1), 1 ether);
        assertEq(stETH.totalSupply(), 1 ether);
        assertEq(wstETH.balanceOf(USER_1), 0);
        assertEq(wstETH.totalSupply(), 0);

        vm.startBroadcast(USER_1);
        stETH.approve(address(wstETH), 1 ether);
        wstETH.wrap(1 ether);
        vm.stopBroadcast();

        assertEq(stETH.balanceOf(USER_1), 0);
        assertEq(stETH.totalSupply(), 1 ether);
        assertEq(stETH.balanceOf(address(wstETH)), 1 ether);
        assertEq(wstETH.totalSupply(), 1 ether);
        assertEq(wstETH.balanceOf(USER_1), 1 ether);
    }

    function test_unwrap() public {
        test_wrap();

        vm.startBroadcast(USER_1);
        wstETH.unwrap(1 ether);
        vm.stopBroadcast();

        assertEq(stETH.balanceOf(USER_1), 1 ether);
        assertEq(stETH.totalSupply(), 1 ether);
        assertEq(stETH.balanceOf(address(wstETH)), 0);
        assertEq(wstETH.totalSupply(), 0);
        assertEq(wstETH.balanceOf(USER_1), 0);
    }

    function test_receive() public {
        assertEq(USER_1.balance, 1 ether);
        assertEq(stETH.balanceOf(USER_1), 1 ether);
        assertEq(stETH.totalSupply(), 1 ether);
        assertEq(wstETH.balanceOf(USER_1), 0);
        assertEq(wstETH.totalSupply(), 0);

        vm.startBroadcast(USER_1);
        (bool success,) = payable(wstETH).call{ value: 1 ether }("");
        vm.stopBroadcast();

        assertTrue(success);
        assertEq(USER_1.balance, 0);
        assertEq(stETH.balanceOf(USER_1), 1 ether);
        assertEq(stETH.totalSupply(), 2 ether);
        assertEq(stETH.balanceOf(address(wstETH)), 1 ether);
        assertEq(wstETH.totalSupply(), 1 ether);
        assertEq(wstETH.balanceOf(USER_1), 1 ether);
    }
}

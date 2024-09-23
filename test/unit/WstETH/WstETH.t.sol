// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { WstEthFixture } from "./utils/Fixtures.sol";

/**
 * @custom:feature Test functions in `wstEth`
 */
contract TestWstEth is WstEthFixture {
    function setUp() public override {
        super.setUp();
        stETH.mint(address(this), 1 ether);
    }

    function test_wrap() public {
        assertEq(stETH.balanceOf(address(this)), 1 ether);
        assertEq(stETH.totalSupply(), 1 ether);
        assertEq(wstETH.balanceOf(address(this)), 0);
        assertEq(wstETH.totalSupply(), 0);

        stETH.approve(address(wstETH), 1 ether);
        wstETH.wrap(1 ether);

        assertEq(stETH.balanceOf(address(this)), 0);
        assertEq(stETH.totalSupply(), 1 ether);
        assertEq(stETH.balanceOf(address(wstETH)), 1 ether);
        assertEq(wstETH.totalSupply(), 1 ether);
        assertEq(wstETH.balanceOf(address(this)), 1 ether);
    }

    function test_unwrap() public {
        test_wrap();

        wstETH.unwrap(1 ether);

        assertEq(stETH.balanceOf(address(this)), 1 ether);
        assertEq(stETH.totalSupply(), 1 ether);
        assertEq(stETH.balanceOf(address(wstETH)), 0);
        assertEq(wstETH.totalSupply(), 0);
        assertEq(wstETH.balanceOf(address(this)), 0);
    }

    function test_receive() public {
        uint256 oldBalance = address(this).balance;
        assertEq(stETH.balanceOf(address(this)), 1 ether);
        assertEq(stETH.totalSupply(), 1 ether);
        assertEq(wstETH.balanceOf(address(this)), 0);
        assertEq(wstETH.totalSupply(), 0);

        (bool success,) = payable(wstETH).call{ value: 1 ether }("");

        assertTrue(success);
        assertEq(oldBalance - address(this).balance, 1 ether);
        assertEq(stETH.balanceOf(address(this)), 1 ether);
        assertEq(stETH.totalSupply(), 2 ether);
        assertEq(stETH.balanceOf(address(wstETH)), 1 ether);
        assertEq(wstETH.totalSupply(), 1 ether);
        assertEq(wstETH.balanceOf(address(this)), 1 ether);
    }
}

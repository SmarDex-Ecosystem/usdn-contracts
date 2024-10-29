// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { WstEthFixture } from "./utils/Fixtures.sol";

/**
 * @custom:feature Test functions in `StEth`
 */
contract TestStEth is WstEthFixture {
    function setUp() public override {
        super.setUp();
    }

    function test_submit() public {
        uint256 oldBalance = address(this).balance;
        assertEq(stETH.balanceOf(address(this)), 0);

        stETH.submit{ value: 1 ether }(address(this));

        assertEq(oldBalance - address(this).balance, 1 ether);
        assertEq(stETH.balanceOf(address(this)), 1 ether);
    }

    function test_receive() public {
        uint256 oldBalance = address(this).balance;
        assertEq(stETH.balanceOf(address(this)), 0);

        (bool success,) = payable(stETH).call{ value: 1 ether }("");

        assertTrue(success);
        assertEq(oldBalance - address(this).balance, 1 ether);
        assertEq(stETH.balanceOf(address(this)), 1 ether);
    }

    function test_sweep() public {
        uint256 ethAmount = 2 ether;
        (bool success,) = address(wstETH).call{ value: ethAmount }("");
        assertTrue(success);

        uint256 balanceBefore = address(this).balance;
        stETH.sweep(payable(address(this)));

        assertEq(address(wstETH).balance, 0);
        assertGt(wstETH.balanceOf(address(this)), 0);
        assertEq(balanceBefore + 2 ether, address(this).balance);
    }

    receive() external payable { }
}

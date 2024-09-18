// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { USER_1 } from "../../utils/Constants.sol";
import { WstEthFixture } from "./utils/Fixtures.sol";

/**
 * @custom:feature Test functions in `StEth`
 */
contract TestStEth is WstEthFixture {
    function setUp() public override {
        super.setUp();
        deal(USER_1, 1 ether);
    }

    function test_submit() public {
        assertEq(USER_1.balance, 1 ether);
        assertEq(stETH.balanceOf(USER_1), 0);

        vm.startBroadcast(USER_1);
        stETH.submit{ value: 1 ether }(USER_1);
        vm.stopBroadcast();

        assertEq(USER_1.balance, 0);
        assertEq(stETH.balanceOf(USER_1), 1 ether);
    }

    function test_receive() public {
        assertEq(USER_1.balance, 1 ether);
        assertEq(stETH.balanceOf(USER_1), 0);

        vm.startBroadcast(USER_1);
        (bool success,) = payable(stETH).call{ value: 1 ether }("");
        vm.stopBroadcast();

        assertTrue(success);
        assertEq(USER_1.balance, 0);
        assertEq(stETH.balanceOf(USER_1), 1 ether);
    }
}

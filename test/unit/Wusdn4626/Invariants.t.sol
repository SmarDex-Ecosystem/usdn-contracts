// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { Wusdn4626Fixture } from "./utils/Fixtures.sol";

contract TestWusdn4626Invariants is Wusdn4626Fixture {
    function setUp() public override {
        super.setUp();
        address user1 = wusdn4626.USER_1();
        address user2 = wusdn4626.USER_2();
        address user3 = wusdn4626.USER_3();
        address user4 = wusdn4626.USER_4();

        targetContract(address(wusdn4626));

        bytes4[] memory wusdn4626Selectors = new bytes4[](4);
        wusdn4626Selectors[0] = wusdn4626.depositTest.selector;
        wusdn4626Selectors[1] = wusdn4626.mintTest.selector;
        wusdn4626Selectors[2] = wusdn4626.withdrawTest.selector;
        wusdn4626Selectors[3] = wusdn4626.redeemTest.selector;
        targetSelector(FuzzSelector({ addr: address(wusdn4626), selectors: wusdn4626Selectors }));

        targetSender(user1);
        targetSender(user2);
        targetSender(user3);
        targetSender(user4);

        usdn.mint(user1, 1_000_000 ether);
        usdn.mint(user2, 1_000_000 ether);
        usdn.mint(user3, 1_000_000 ether);
        usdn.mint(user4, 1_000_000 ether);

        vm.prank(user1);
        usdn.approve(address(wusdn4626), type(uint256).max);
        vm.prank(user2);
        usdn.approve(address(wusdn4626), type(uint256).max);
        vm.prank(user3);
        usdn.approve(address(wusdn4626), type(uint256).max);
        vm.prank(user4);
        usdn.approve(address(wusdn4626), type(uint256).max);
    }

    function invariant_totalAssetsSum() public view {
        assertEq(wusdn4626.totalSupply(), wusdn4626.getGhostTotalSupply(), "total supply = sum of balances");
    }

    function invariant_totalSupply() public view {
        assertGe(wusdn.balanceOf(address(wusdn4626)), wusdn4626.totalSupply(), "balance of WUSDN >= total supply");
    }
}

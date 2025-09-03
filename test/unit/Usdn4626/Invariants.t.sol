// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { Usdn4626Fixture } from "./utils/Fixtures.sol";

contract TestUsdn4626Invariants is Usdn4626Fixture {
    function setUp() public override {
        super.setUp();
        address user1 = usdn4626.USER_1();
        address user2 = usdn4626.USER_2();
        address user3 = usdn4626.USER_3();
        address user4 = usdn4626.USER_4();

        targetContract(address(usdn4626));

        bytes4[] memory wusdn4626Selectors = new bytes4[](10);
        wusdn4626Selectors[0] = usdn4626.depositTest.selector;
        wusdn4626Selectors[1] = usdn4626.mintTest.selector;
        wusdn4626Selectors[2] = usdn4626.withdrawTest.selector;
        wusdn4626Selectors[3] = usdn4626.redeemTest.selector;
        wusdn4626Selectors[4] = usdn4626.transferTest.selector;
        wusdn4626Selectors[5] = usdn4626.transferFromTest.selector;
        wusdn4626Selectors[6] = usdn4626.approveTest.selector;
        wusdn4626Selectors[7] = usdn4626.mintUsdn.selector;
        wusdn4626Selectors[8] = usdn4626.rebaseTest.selector;
        wusdn4626Selectors[9] = usdn4626.giftUsdn.selector;
        targetSelector(FuzzSelector({ addr: address(usdn4626), selectors: wusdn4626Selectors }));

        targetSender(user1);
        targetSender(user2);
        targetSender(user3);
        targetSender(user4);

        usdn.mint(user1, 100_000_000 ether);
        usdn.mint(user2, 100_000_000 ether);
        usdn.mint(user3, 100_000_000 ether);
        usdn.mint(user4, 100_000_000 ether);

        vm.prank(user1);
        usdn.approve(address(usdn4626), type(uint256).max);
        vm.prank(user2);
        usdn.approve(address(usdn4626), type(uint256).max);
        vm.prank(user3);
        usdn.approve(address(usdn4626), type(uint256).max);
        vm.prank(user4);
        usdn.approve(address(usdn4626), type(uint256).max);
    }

    function invariant_worker1() public view {
        assertInvariants();
    }

    function invariant_worker2() public view {
        assertInvariants();
    }

    function invariant_worker3() public view {
        assertInvariants();
    }

    function invariant_worker4() public view {
        assertInvariants();
    }

    function invariant_worker5() public view {
        assertInvariants();
    }

    function invariant_worker6() public view {
        assertInvariants();
    }

    function invariant_worker7() public view {
        assertInvariants();
    }

    function invariant_worker8() public view {
        assertInvariants();
    }

    function assertInvariants() internal view {
        assertEq(usdn4626.totalSupply(), usdn4626.getGhostTotalSupply(), "total supply = sum of balances");
        assertGe(usdn.sharesOf(address(usdn4626)) / 1e18, usdn4626.totalSupply(), "balance of USDN >= total supply");
        assertLe(usdn4626.totalSupply(), type(uint256).max / 1e18, "total supply <= uint256.max / SHARES_RATIO");
    }

    function afterInvariant() public {
        usdn4626.redeemAll();
        assertEq(usdn4626.totalSupply(), 0, "total supply after redeemAll");
        usdn4626.emptyVault();
        assertLt(usdn.sharesOf(address(usdn4626)), 1e18, "usdn balance of contract");
    }
}

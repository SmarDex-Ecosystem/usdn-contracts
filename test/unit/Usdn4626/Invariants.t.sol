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

        bytes4[] memory wusdn4626Selectors = new bytes4[](6);
        wusdn4626Selectors[0] = usdn4626.depositTest.selector;
        wusdn4626Selectors[1] = usdn4626.mintTest.selector;
        wusdn4626Selectors[2] = usdn4626.withdrawTest.selector;
        wusdn4626Selectors[3] = usdn4626.redeemTest.selector;
        wusdn4626Selectors[4] = usdn4626.rebaseTest.selector;
        wusdn4626Selectors[5] = usdn4626.giftUsdn.selector;
        targetSelector(FuzzSelector({ addr: address(usdn4626), selectors: wusdn4626Selectors }));

        targetSender(user1);
        targetSender(user2);
        targetSender(user3);
        targetSender(user4);

        usdn.mint(user1, 1_000_000 ether);
        usdn.mint(user2, 1_000_000 ether);
        usdn.mint(user3, 1_000_000 ether);
        usdn.mint(user4, 1_000_000 ether);

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
        assertGe(usdn.sharesOf(address(usdn4626)), usdn4626.totalSupply(), "balance of USDN >= total supply");
    }

    function testFuzz_convertToShares(uint256 assets, uint256 divisor) public {
        divisor = bound(divisor, usdn.MIN_DIVISOR(), usdn.MAX_DIVISOR());
        assets = bound(assets, 0, usdn.maxTokens());
        if (divisor < usdn.MAX_DIVISOR()) {
            usdn.rebase(divisor);
        }
        uint256 shares = usdn4626.convertToShares(assets);
        assertEq(shares, usdn.convertToShares(assets), "USDN.convertToShares");
        assertEq(shares, usdn4626.previewDeposit(assets), "previewDeposit");
    }

    function testFuzz_convertToAssets(uint256 shares, uint256 divisor) public {
        divisor = bound(divisor, usdn.MIN_DIVISOR(), usdn.MAX_DIVISOR());
        if (divisor < usdn.MAX_DIVISOR()) {
            usdn.rebase(divisor);
        }
        uint256 assets = usdn4626.convertToAssets(shares);
        assertLe(assets, usdn.convertToTokens(shares), "USDN.convertToTokens");
        assertApproxEqAbs(assets, usdn.convertToTokens(shares), 1, "USDN.convertToTokens 1 wei off max");
        assertLe(assets, usdn4626.previewRedeem(shares), "previewRedeem");
        assertApproxEqAbs(assets, usdn4626.previewRedeem(shares), 1, "previewRedeem 1 wei off max");
    }
}

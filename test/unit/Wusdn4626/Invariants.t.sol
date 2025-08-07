// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { Wusdn4626Fixture } from "./utils/Fixtures.sol";

contract TestWusdn4626Invariants is Wusdn4626Fixture {
    function setUp() public override {
        super.setUp();
        targetContract(address(wusdn4626));

        bytes4[] memory wusdn4626Selectors = new bytes4[](4);
        wusdn4626Selectors[0] = wusdn4626.depositTest.selector;
        wusdn4626Selectors[1] = wusdn4626.mintTest.selector;
        wusdn4626Selectors[2] = wusdn4626.withdrawTest.selector;
        wusdn4626Selectors[3] = wusdn4626.redeemTest.selector;
        targetSelector(FuzzSelector({ addr: address(wusdn4626), selectors: wusdn4626Selectors }));

        targetSender(wusdn4626.USER_1());
        targetSender(wusdn4626.USER_2());
        targetSender(wusdn4626.USER_3());
        targetSender(wusdn4626.USER_4());

        usdn.mint(wusdn4626.USER_1(), 1_000_000 ether);
        usdn.mint(wusdn4626.USER_2(), 1_000_000 ether);
        usdn.mint(wusdn4626.USER_3(), 1_000_000 ether);
        usdn.mint(wusdn4626.USER_4(), 1_000_000 ether);

        vm.prank(wusdn4626.USER_1());
        usdn.approve(address(wusdn4626), type(uint256).max);
        vm.prank(wusdn4626.USER_2());
        usdn.approve(address(wusdn4626), type(uint256).max);
        vm.prank(wusdn4626.USER_3());
        usdn.approve(address(wusdn4626), type(uint256).max);
        vm.prank(wusdn4626.USER_4());
        usdn.approve(address(wusdn4626), type(uint256).max);
    }

    function invariant_totalAssetsSum() public view {
        assertEq(wusdn4626.totalSupply(), wusdn4626.getGhostTotBal());
    }

    function invariant_totalAssetsVsTotalSupply() public view {
        // the total assets should always be gte than the total supply because of the shares
        assertGe(wusdn4626.totalAssets(), wusdn4626.totalSupply());
    }

    function invariant_redeemAll() public view {
        uint256 usdnBalance = wusdn.previewUnwrap(wusdn.balanceOf(address(wusdn4626)));
        uint256 totalSupply = wusdn4626.totalSupply();

        assertEq(wusdn4626.previewRedeem(totalSupply), usdnBalance);
    }
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { USER_1 } from "test/utils/Constants.sol";
import { UsdnTokenFixture } from "test/unit/USDN/utils/Fixtures.sol";

import { Wusdn } from "src/Wusdn.sol";

/**
 * @custom:feature The `withdraw` function of `WUSDN`
 * @custom:background  Given this contract has the MINTER_ROLE and mint tokens to USER_1
 * and the user has deposited 1 usdn in wusdn contract
 */
contract TestWusdnWithdraw is UsdnTokenFixture {
    Wusdn wusdn;

    function setUp() public override {
        super.setUp();

        usdn.grantRole(usdn.MINTER_ROLE(), address(this));
        usdn.mint(USER_1, 100 ether);

        wusdn = new Wusdn(usdn);

        vm.startPrank(USER_1);
        usdn.approve(address(wusdn), type(uint256).max);
        wusdn.deposit(1 ether, USER_1);
        vm.stopPrank();
    }

    /**
     * @custom:scenario Test the withdraw function
     * @custom:given The user has deposited 1 ether
     * @custom:when The user initiates a withdraw of 0.1 ether
     * @custom:then The user's balance increases by 0.1 ether
     * @custom:then The user's share of wusdn decreases by the expected amount
     */
    function test_withdraw_to_wusdn() public {
        uint256 shares = wusdn.previewWithdraw(0.1 ether);
        uint256 balanceBeforeWithdraw = usdn.balanceOf(USER_1);
        uint256 shareBeforeWithdraw = wusdn.balanceOf(USER_1);
        vm.startPrank(USER_1);
        wusdn.withdraw(0.1 ether, USER_1, USER_1);
        vm.stopPrank();
        assertEq(usdn.balanceOf(USER_1) - balanceBeforeWithdraw, 0.1 ether, "total supply");
        assertEq(shareBeforeWithdraw - wusdn.balanceOf(USER_1), shares, "total shares");
    }
}

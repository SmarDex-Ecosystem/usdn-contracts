// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { USER_1, USER_2, USER_3, USER_4 } from "test/utils/Constants.sol";
import { UsdnTokenFixture } from "test/unit/USDN/utils/Fixtures.sol";

import { Wusdn } from "src/Wusdn.sol";

/**
 * @custom:feature The `withdraw` function of `WUSDN`
 * @custom:background  Given this contract has the MINTER_ROLE and mint tokens to USER_1
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
     * @custom:when The user initiates a withdraw of 1 ether
     * @custom:then The user's balance increases by 1 ether
     */
    function test_withdraw() public {
        uint256 shares = wusdn.previewWithdraw(1 ether);
        uint256 balanceBeforeWithdraw = usdn.balanceOf(address(USER_1));
        uint256 shareBeforeWithdraw = wusdn.balanceOf(address(USER_1));
        vm.startPrank(USER_1);
        wusdn.withdraw(1 ether, USER_1, USER_1);
        vm.stopPrank();
        uint256 balanceAfterwithdraw = usdn.balanceOf(address(USER_1));
        uint256 shareAfterwithdraw = wusdn.balanceOf(address(USER_1));
        require(balanceAfterwithdraw - balanceBeforeWithdraw > 0, "Wusdn: withdraw failed");
        require(balanceAfterwithdraw - balanceBeforeWithdraw == 1 ether, "Wusdn: withdraw balance mismatch");
        require(shareBeforeWithdraw - shareAfterwithdraw == shares, "Wusdn: withdraw shares mismatch");
    }
}

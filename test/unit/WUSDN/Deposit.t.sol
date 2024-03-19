// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { USER_1 } from "test/utils/Constants.sol";
import { UsdnTokenFixture } from "test/unit/USDN/utils/Fixtures.sol";

import { Wusdn } from "src/Wusdn.sol";

/**
 * @custom:feature The `deposit` function of `WUSDN`
 * @custom:background  Given this contract has the MINTER_ROLE and mint tokens to USER_1
 */
contract TestWusdnDeposit is UsdnTokenFixture {
    Wusdn wusdn;

    function setUp() public override {
        super.setUp();

        usdn.grantRole(usdn.MINTER_ROLE(), address(this));
        usdn.mint(USER_1, 100 ether);

        wusdn = new Wusdn(usdn);
    }

    /**
     * @custom:scenario Test deposit function
     * @custom:given The user has initiated a deposit
     * @custom:and The validation deadline has elapsed
     * @custom:when The test_deposit function is called
     * @custom:then The deposit is successful
     */
    function test_deposit_to_wusdn() public {
        uint256 shares = wusdn.previewDeposit(1 ether);
        uint256 balanceBeforeDeposit = usdn.balanceOf(address(USER_1));
        uint256 shareBeforeDeposit = wusdn.balanceOf(address(USER_1));
        vm.startPrank(USER_1);
        usdn.approve(address(wusdn), type(uint256).max);
        wusdn.deposit(1 ether, USER_1);
        vm.stopPrank();
        assertGt(balanceBeforeDeposit, usdn.balanceOf(address(USER_1)), "deposit failed");
        assertEq(balanceBeforeDeposit - usdn.balanceOf(address(USER_1)), 1 ether, "total supply");
        assertEq(wusdn.balanceOf(address(USER_1)) - shareBeforeDeposit, shares, "total shares");
    }
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";

import { USER_1 } from "test/utils/Constants.sol";
import { UsdnTokenFixture } from "test/unit/USDN/utils/Fixtures.sol";

contract TestUsdnAdjust is UsdnTokenFixture {
    function setUp() public override {
        super.setUp();
    }

    function test_adjustMultiplier() public {
        usdn.grantRole(usdn.MINTER_ROLE(), address(this));
        usdn.mint(USER_1, 100 ether);
        usdn.grantRole(usdn.ADJUSTMENT_ROLE(), address(this));
        vm.expectEmit(true, true, false, false, address(usdn));
        emit MultiplierAdjusted(1 ether, 1 ether + 1); // expected event
        usdn.adjustMultiplier(1 ether + 1);
        assertEq(usdn.sharesOf(USER_1), 100 ether);
        assertEq(usdn.balanceOf(USER_1), 100 ether + 100);
    }

    function test_RevertWhen_unauthorized() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, address(this), usdn.ADJUSTMENT_ROLE()
            )
        );
        usdn.adjustMultiplier(2 ether);
    }

    function test_RevertWhen_invalidMultiplier() public {
        usdn.grantRole(usdn.ADJUSTMENT_ROLE(), address(this));
        vm.expectRevert(abi.encodeWithSelector(InvalidMultiplier.selector, 1 ether));
        usdn.adjustMultiplier(1 ether);
        vm.expectRevert(abi.encodeWithSelector(InvalidMultiplier.selector, 0.5 ether));
        usdn.adjustMultiplier(0.5 ether);
    }
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";

import { ADMIN } from "test/utils/Constants.sol";
import { UsdnTokenFixture } from "test/unit/USDN/utils/Fixtures.sol";

import { IRebaseCallback } from "src/interfaces/Usdn/IRebaseCallback.sol";

/**
 * @custom:feature The admin functions of the USDN token
 * @custom:background The default admin role is only given to ADMIN
 */
contract TestUsdnAdmin is UsdnTokenFixture {
    function setUp() public override {
        super.setUp();
        usdn.grantRole(usdn.DEFAULT_ADMIN_ROLE(), ADMIN);
        usdn.revokeRole(usdn.DEFAULT_ADMIN_ROLE(), address(this));
    }

    /**
     * @custom:scenario Update the rebase handler
     * @custom:given The ADMIN account has DEFAULT_ADMIN_ROLE
     * @custom:when The ADMIN account calls `setRebaseHandler`
     * @custom:then The value of the rebase handler address is updated to the new value
     * @custom:and The `RebaseHandlerUpdated` event is emitted with the correct parameter
     */
    function test_setRebaseHandler() public {
        address newValue = address(1);
        IRebaseCallback handler = IRebaseCallback(newValue);
        vm.expectEmit();
        emit RebaseHandlerUpdated(handler);
        vm.prank(ADMIN);
        usdn.setRebaseHandler(handler);
        assertEq(address(usdn.rebaseHandler()), newValue);
    }
}

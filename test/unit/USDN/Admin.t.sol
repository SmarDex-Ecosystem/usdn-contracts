// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { ADMIN } from "../../utils/Constants.sol";
import { UsdnTokenFixture } from "./utils/Fixtures.sol";

import { IRebaseCallback } from "../../../src/interfaces/Usdn/IRebaseCallback.sol";

/**
 * @custom:feature The admin functions of the USDN token
 * @custom:background The default admin role is only given to ADMIN
 */
contract TestUsdnAdmin is UsdnTokenFixture {
    function setUp() public override {
        super.setUp();
        usdn.grantRole(usdn.DEFAULT_ADMIN_ROLE(), ADMIN);
        usdn.renounceRole(usdn.DEFAULT_ADMIN_ROLE(), address(this));
    }

    /**
     * @custom:scenario Update the rebase handler
     * @custom:given The ADMIN account has DEFAULT_ADMIN_ROLE
     * @custom:when The ADMIN account calls `setRebaseHandler`
     * @custom:then The value of the rebase handler address is updated to the new value
     * @custom:and The `RebaseHandlerUpdated` event is emitted with the correct parameter
     */
    function test_setRebaseHandler() public adminPrank {
        address newValue = address(1);
        IRebaseCallback handler = IRebaseCallback(newValue);
        vm.expectEmit();
        emit RebaseHandlerUpdated(handler);
        usdn.setRebaseHandler(handler);
        assertEq(address(usdn.rebaseHandler()), newValue);
    }
}

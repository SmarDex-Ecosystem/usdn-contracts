// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";

import { UsdnTokenFixture } from "./utils/Fixtures.sol";

import { IRebaseCallback } from "../../../src/interfaces/Usdn/IRebaseCallback.sol";
import { SetRebaseHandlerManager } from "../../../src/utils/SetRebaseHandlerManager.sol";

/**
 * @custom:feature The `setRebaseHandler` function of `SetRebaseHandlerManager`.
 * @custom:background The `SetRebaseHandlerManager` contract is used to set the rebase handler in the USDN token.
 */
contract TestSetRebaseHandlerManager is UsdnTokenFixture {
    SetRebaseHandlerManager public setRebaseHandlerManager;

    function setUp() public override {
        super.setUp();

        setRebaseHandlerManager = new SetRebaseHandlerManager(usdn, address(this));
        usdn.grantRole(usdn.DEFAULT_ADMIN_ROLE(), address(setRebaseHandlerManager));
        usdn.revokeRole(usdn.DEFAULT_ADMIN_ROLE(), address(this));
    }

    /**
     * @custom:scenario Call `setRebaseHandler` functions and check rebaseHandler change on USDN.
     * @custom:given The setRebaseHandlerManager has the right role.
     * @custom:when The `setRebaseHandler` is executed.
     * @custom:then The rebaseHandler should be changed.
     */
    function test_setRebaseHandler() public {
        IRebaseCallback newHandler = IRebaseCallback(address(0x1));
        setRebaseHandlerManager.setRebaseHandler(newHandler);
        assertEq(address(usdn.rebaseHandler()), address(newHandler), "rebaseHandler should be changed");
    }

    /**
     * @custom:scenario Call `renounceUsdnOwnership` functions and check the role is revoked.
     * @custom:given The setRebaseHandlerManager has the right role.
     * @custom:when The `renounceUsdnOwnership` is executed.
     * @custom:then The role should be revoked.
     */
    function test_renounceUsdnOwnership() public {
        setRebaseHandlerManager.renounceUsdnOwnership();
        assertFalse(usdn.hasRole(usdn.DEFAULT_ADMIN_ROLE(), address(setRebaseHandlerManager)), "Role should be revoked");
    }

    /**
     * @custom:scenario Call `setRebaseHandler` functions without the manager contract.
     * @custom:given The caller has no right role.
     * @custom:when A wallet without right role trigger `setRebaseHandler`.
     * @custom:then functions should revert with custom "AccessControlUnauthorizedAccount" error.
     */
    function test_RevertWhen_setRebaseHandlerWithoutManager() public {
        IRebaseCallback newHandler = IRebaseCallback(address(0x1));
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, address(this), usdn.DEFAULT_ADMIN_ROLE()
            )
        );
        usdn.setRebaseHandler(newHandler);
    }
}

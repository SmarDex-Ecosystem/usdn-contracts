// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { UsdnNoRebaseTokenFixture } from "./utils/Fixtures.sol";

import { IRebaseCallback } from "../../../src/interfaces/Usdn/IRebaseCallback.sol";

/**
 * @custom:feature The `setRebaseHandler` function of `UsdnNoRebase`
 * @custom:background Given this contract is the owner
 */
contract TestUsdnNoRebaseSetRebaseHandler is UsdnNoRebaseTokenFixture {
    function setUp() public override {
        super.setUp();
        assertEq(address(usdn.rebaseHandler()), address(0), "The rebase handler cannot be set in a no rebase setup");
    }

    /**
     * @custom:scenario Update the rebase handler
     * @custom:when `setRebaseHandler` is called
     * @custom:then The call reverts with a `UsdnRebaseNotSupported` error
     */
    function test_RevertWhen_setRebaseHandler() public {
        vm.expectRevert(UsdnRebaseNotSupported.selector);
        usdn.setRebaseHandler(IRebaseCallback(address(0)));
    }
}

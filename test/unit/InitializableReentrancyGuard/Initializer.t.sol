// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { InitializableReentrancyGuardFixtures } from "./utils/Fixtures.sol";

import { InitializableReentrancyGuard } from "../../../src/utils/InitializableReentrancyGuard.sol";

/**
 * @custom:feature Unit tests for the `initializer` modifier of the InitializableReentrancyGuard contract
 */
contract TestInitializableReentrancyGuardInitializer is
    InitializableReentrancyGuardFixtures,
    InitializableReentrancyGuard
{
    /**
     * @custom:scenario The user calls a function with the initializer modifier in an uninitialized contract
     * @custom:given an uninitialized contract
     * @custom:when The user calls a function with the initializer modifier
     * @custom:then The status of the contract is set to NOT_ENTERED
     */
    function test_initializeSetStatusToNotEntered() public {
        // Load the storage slot for the `_status` private storage variable
        uint256 statusBefore = handler.i_getInitializableReentrancyGuardStorage()._status;

        // sanity check
        assertEq(statusBefore, 0, "Status must be UNINITIALIZED");

        handler.initialize();

        uint256 statusAfter = handler.i_getInitializableReentrancyGuardStorage()._status;
        assertEq(statusAfter, 1, "Status should be NOT_ENTERED");
    }

    /**
     * @custom:scenario The user calls a function with the initializer modifier twice
     * @custom:given an initialized contract with a function that initializes it
     * @custom:when The user calls a function with the initializer modifier twice
     * @custom:then The second call reverts with a InitializableReentrancyGuardInvalidInitialization error
     */
    function test_RevertWhen_alreadyInitialized() public {
        handler.initialize();

        vm.expectRevert(InitializableReentrancyGuardInvalidInitialization.selector);
        handler.initialize();
    }
}

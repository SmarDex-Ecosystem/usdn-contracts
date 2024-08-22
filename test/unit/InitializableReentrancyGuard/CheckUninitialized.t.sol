// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { InitializableReentrancyGuardFixtures } from "./utils/Fixtures.sol";

import { InitializableReentrancyGuard } from "../../../src/utils/InitializableReentrancyGuard.sol";

/**
 * @custom:feature Unit tests for the `_checkUninitialized` function of the InitializableReentrancyGuard contract
 */
contract TestInitializableReentrancyGuardCheckUninitialized is
    InitializableReentrancyGuardFixtures,
    InitializableReentrancyGuard
{
    /**
     * @custom:scenario The user calls _checkUninitialized in an uninitialized contract
     * @custom:given an uninitialized contract
     * @custom:when The user calls _checkUninitialized
     * @custom:then The call does not revert
     */
    function test_checkUninitialized() public view {
        handler.i_checkUninitialized();
    }

    /**
     * @custom:scenario The user calls _checkUninitialized in an initialized contract
     * @custom:given An initialized contract
     * @custom:when The user calls _checkUninitialized
     * @custom:then The call reverts with a InitializableReentrancyGuardInvalidInitialization error
     */
    function test_RevertWhen_notInitialized() public {
        handler.initialize();

        vm.expectRevert(InitializableReentrancyGuardInvalidInitialization.selector);
        handler.i_checkUninitialized();
    }
}

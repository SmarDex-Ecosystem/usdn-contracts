// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { InitializableReentrancyGuardFixtures } from "./utils/Fixtures.sol";

import { InitializableReentrancyGuard } from "../../../src/utils/InitializableReentrancyGuard.sol";

/**
 * @custom:feature Unit tests for the `initializedAndNonReentrant` modifier of the InitializableReentrancyGuard contract
 */
contract TestInitializableReentrancyGuardInitializedAndNonReentrant is
    InitializableReentrancyGuardFixtures,
    InitializableReentrancyGuard
{
    bool internal _reenter;

    /**
     * @custom:scenario The user calls a function with the initializedAndNonReentrant modifier
     * in an uninitialized contract
     * @custom:given An uninitialized contract
     * @custom:when The user calls a function with the initializedAndNonReentrant modifier
     * @custom:then The call reverts with a InitializableReentrancyGuardUninitialized error
     */
    function test_RevertWhen_notInitialized() public {
        vm.expectRevert(InitializableReentrancyGuardUninitialized.selector);
        handler.func_initializedAndNonReentrant();
    }

    /**
     * @custom:scenario The user reenters a function with the initializedAndNonReentrant modifier
     * @custom:given A user being a smart contract that calls the same function when receiving ether
     * @custom:and an initialized contract with a function that sends ether to the caller
     * @custom:when The user calls a function with the initializedAndNonReentrant modifier
     * @custom:then The call reverts with a InitializableReentrancyGuardReentrantCall error
     */
    function test_RevertWhen_reentrant() public {
        uint256 status = handler.i_getInitializableReentrancyGuardStorage()._status;
        if (_reenter) {
            assertEq(status, 2, "Status should be ENTERED");

            vm.expectRevert(InitializableReentrancyGuardReentrantCall.selector);
            handler.func_initializedAndNonReentrant();
            return;
        }

        // Sanity check
        assertEq(status, 0, "Status should be UNINITIALIZED");
        handler.initialize();
        _reenter = true;

        // Make sure a reentrancy happened
        vm.expectCall(address(handler), abi.encodeWithSelector(handler.func_initializedAndNonReentrant.selector), 2);
        handler.func_initializedAndNonReentrant();

        status = handler.i_getInitializableReentrancyGuardStorage()._status;
        assertEq(status, 1, "Status should be NOT_ENTERED");
    }

    /**
     * @custom:scenario The user reenters a function with the initializedAndNonReentrant modifier
     * @custom:given A user being a smart contract that can receive ether
     * @custom:and an initialized contract with a function that sends ether to the caller
     * @custom:when The user calls a function with the modifier
     * @custom:then The call does not revert and there is no reentrancy
     */
    function test_initializedAndNonReentrant() public {
        handler.initialize();

        // Make sure no reentrancy happened
        vm.expectCall(address(handler), abi.encodeWithSelector(handler.func_initializedAndNonReentrant.selector), 1);
        handler.func_initializedAndNonReentrant();
    }

    receive() external payable {
        if (_reenter) {
            test_RevertWhen_reentrant();
            _reenter = false;
        }
    }
}

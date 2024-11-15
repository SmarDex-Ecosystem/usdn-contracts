// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { ReentrancyGuardTransientUpgradeable } from
    "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardTransientUpgradeable.sol";

import { InitializableReentrancyGuardFixtures } from "./utils/Fixtures.sol";

import { InitializableReentrancyGuard } from "../../../src/utils/InitializableReentrancyGuard.sol";

/**
 * @custom:feature Unit tests for the `initialized` modifier of the InitializableReentrancyGuard contract
 */
contract TestInitializableReentrancyGuardInitializedAndNonReentrant is
    InitializableReentrancyGuardFixtures,
    InitializableReentrancyGuard,
    ReentrancyGuardTransientUpgradeable
{
    bool internal _reenter;

    /**
     * @custom:scenario The user calls a function with the initialized modifier
     * in an uninitialized contract
     * @custom:given An uninitialized contract
     * @custom:when The user calls a function with the initialized modifier
     * @custom:then The call reverts with a InitializableReentrancyGuardUninitialized error
     */
    function test_RevertWhen_notInitialized() public {
        vm.expectRevert(InitializableReentrancyGuardUninitialized.selector);
        handler.func_initializedAndNonReentrant();
    }

    /**
     * @custom:scenario The user reenters a function with the initialized modifier
     * @custom:given A user being a smart contract that calls the same function when receiving ether
     * @custom:and an initialized contract with a function that sends ether to the caller
     * @custom:when The user calls a function with the initialized modifier
     * @custom:then The call reverts with a ReentrancyGuardReentrantCall error
     */
    function test_RevertWhen_reentrant() public {
        bool entered = handler.i_reentrancyGuardEntered();
        if (_reenter) {
            assertTrue(entered, "Should be entered");

            vm.expectRevert(ReentrancyGuardReentrantCall.selector);
            handler.func_initializedAndNonReentrant();
            return;
        }

        // Sanity check
        assertFalse(entered, "Should not be entered");
        handler.initialize();
        _reenter = true;

        // Make sure a reentrancy happened
        vm.expectCall(address(handler), abi.encodeWithSelector(handler.func_initializedAndNonReentrant.selector), 2);
        handler.func_initializedAndNonReentrant();

        entered = handler.i_reentrancyGuardEntered();
        assertFalse(entered, "Should not be entered");
    }

    /**
     * @custom:scenario The user reenters a function with the initialized modifier
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

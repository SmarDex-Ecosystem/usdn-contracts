// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { BaseFixture } from "test/utils/Fixtures.sol";
import { DequeHandler } from "test/unit/DoubleEndedQueue/utils/Handler.sol";

import { PendingAction } from "src/libraries/DoubleEndedQueue.sol";

/**
 * @title DequeFixture
 * @dev Utils for testing DoubleEndedQueue.sol
 */
contract DequeFixture is BaseFixture {
    DequeHandler public handler; // wrapper to get gas usage report

    function setUp() public virtual {
        handler = new DequeHandler();
    }

    /**
     * @dev Helper function to assert two `PendingAction` are equal.
     * Reverts if not equal.
     * @param a First `PendingAction`
     * @param b Second `PendingAction`
     */
    function _assertActionsEqual(PendingAction memory a, PendingAction memory b) internal {
        assertTrue(a.action == b.action);
        assertEq(a.timestamp, b.timestamp);
        assertEq(a.user, b.user);
        assertEq(a.tick, b.tick);
        assertEq(a.amountOrIndex, b.amountOrIndex);
    }

    // force ignore from coverage report
    // until https://github.com/foundry-rs/foundry/issues/2988 is fixed
    function test() public override { }
}

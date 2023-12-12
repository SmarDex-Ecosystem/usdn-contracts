// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { console2 } from "forge-std/Test.sol";

import { USER_1 } from "test/utils/Constants.sol";
import { DequeFixture } from "test/unit/DoubleEndedQueue/utils/Fixtures.sol";

import { DoubleEndedQueue, ProtocolAction, PendingAction } from "src/libraries/DoubleEndedQueue.sol";

/**
 * @custom:feature Test functions in `DoubleEndedQueue`
 * @custom:background Given the deque is empty
 */
contract TestDequePopulated is DequeFixture {
    PendingAction action1 = PendingAction(ProtocolAction.InitiateWithdrawal, 69, USER_1, 0, 1 ether);
    PendingAction action2 = PendingAction(ProtocolAction.InitiateDeposit, 420, USER_1, -42, 1000 ether);
    PendingAction action3 = PendingAction(ProtocolAction.InitiateOpenPosition, 42, USER_1, 0, 10);
    uint128 rawIndex1;
    uint128 rawIndex2;
    uint128 rawIndex3;

    function setUp() public override {
        super.setUp();

        rawIndex2 = handler.pushBack(action2);
        rawIndex1 = handler.pushFront(action1);
        rawIndex3 = handler.pushBack(action3);
    }

    function test_view() public {
        assertEq(handler.empty(), false);
        assertEq(handler.length(), 3);
    }

    function test_accessFront() public {
        PendingAction memory front = handler.front();
        _assertActionsEqual(front, action1);
    }

    function test_accessBack() public {
        PendingAction memory back = handler.back();
        _assertActionsEqual(back, action3);
    }

    function test_accessAt() public {
        _assertActionsEqual(handler.at(0), action1);
        _assertActionsEqual(handler.at(1), action2);
        _assertActionsEqual(handler.at(2), action3);
    }

    function test_accessAtRaw() public {
        _assertActionsEqual(handler.atRaw(rawIndex1), action1);
        _assertActionsEqual(handler.atRaw(rawIndex2), action2);
        _assertActionsEqual(handler.atRaw(rawIndex3), action3);
    }

    function test_RevertWhen_OOB() public {
        vm.expectRevert(DoubleEndedQueue.QueueOutOfBounds.selector);
        handler.at(3);
        vm.expectRevert(DoubleEndedQueue.QueueOutOfBounds.selector);
        handler.atRaw(3);
    }

    function test_pushFront() public {
        PendingAction memory action = PendingAction(ProtocolAction.InitiateClosePosition, 1, USER_1, 1, 1);
        uint128 rawIndex = handler.pushFront(action);
        uint128 expectedRawIndex;
        unchecked {
            expectedRawIndex = rawIndex1 - 1;
        }
        assertEq(rawIndex, expectedRawIndex);
        _assertActionsEqual(handler.at(0), action);
        _assertActionsEqual(handler.atRaw(rawIndex), action);
        _assertActionsEqual(handler.at(1), action1);
        _assertActionsEqual(handler.atRaw(rawIndex1), action1);
        _assertActionsEqual(handler.at(2), action2);
        _assertActionsEqual(handler.atRaw(rawIndex2), action2);
        _assertActionsEqual(handler.at(3), action3);
        _assertActionsEqual(handler.atRaw(rawIndex3), action3);
    }

    function test_pushBack() public {
        PendingAction memory action = PendingAction(ProtocolAction.InitiateClosePosition, 1, USER_1, 1, 1);
        uint128 rawIndex = handler.pushBack(action);
        uint128 expectedRawIndex;
        unchecked {
            expectedRawIndex = rawIndex3 + 1;
        }
        assertEq(rawIndex, expectedRawIndex);
        _assertActionsEqual(handler.at(3), action);
        _assertActionsEqual(handler.atRaw(rawIndex), action);
        _assertActionsEqual(handler.at(0), action1);
        _assertActionsEqual(handler.atRaw(rawIndex1), action1);
        _assertActionsEqual(handler.at(1), action2);
        _assertActionsEqual(handler.atRaw(rawIndex2), action2);
        _assertActionsEqual(handler.at(2), action3);
        _assertActionsEqual(handler.atRaw(rawIndex3), action3);
    }

    function test_popFront() public {
        PendingAction memory action = handler.popFront();
        _assertActionsEqual(action, action1);
        _assertActionsEqual(handler.at(0), action2);
        _assertActionsEqual(handler.atRaw(rawIndex2), action2);
        _assertActionsEqual(handler.at(1), action3);
        _assertActionsEqual(handler.atRaw(rawIndex3), action3);
    }

    function test_popBack() public {
        PendingAction memory action = handler.popBack();
        _assertActionsEqual(action, action3);
        _assertActionsEqual(handler.at(0), action1);
        _assertActionsEqual(handler.atRaw(rawIndex1), action1);
        _assertActionsEqual(handler.at(1), action2);
        _assertActionsEqual(handler.atRaw(rawIndex2), action2);
    }

    function test_clearAtFront() public {
        handler.clearAt(rawIndex1); // does a popFront
        _assertActionsEqual(handler.at(0), action2);
        _assertActionsEqual(handler.atRaw(rawIndex2), action2);
        _assertActionsEqual(handler.at(1), action3);
        _assertActionsEqual(handler.atRaw(rawIndex3), action3);
    }

    function test_clearAtBack() public {
        handler.clearAt(rawIndex3); // does a popBack
        _assertActionsEqual(handler.at(0), action1);
        _assertActionsEqual(handler.atRaw(rawIndex1), action1);
        _assertActionsEqual(handler.at(1), action2);
        _assertActionsEqual(handler.atRaw(rawIndex2), action2);
    }

    function test_clearAtMiddle() public {
        handler.clearAt(rawIndex2);
        _assertActionsEqual(handler.at(0), action1);
        _assertActionsEqual(handler.atRaw(rawIndex1), action1);
        _assertActionsEqual(handler.at(2), action3);
        _assertActionsEqual(handler.atRaw(rawIndex3), action3);
        PendingAction memory clearedAction = handler.at(1);
        assertTrue(clearedAction.action == ProtocolAction.None);
        assertEq(clearedAction.timestamp, 0);
        assertEq(clearedAction.user, address(0));
        assertEq(clearedAction.tick, 0);
        assertEq(clearedAction.amountOrIndex, 0);
    }

    function test_clearAll() public {
        handler.clearAt(rawIndex1);
        handler.clearAt(rawIndex2);
        handler.clearAt(rawIndex3);
        assertEq(handler.length(), 0);
        assertTrue(handler.empty());
    }
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { console2 } from "forge-std/Test.sol";

import { USER_1 } from "test/utils/Constants.sol";
import { DequeFixture } from "test/unit/DoubleEndedQueue/utils/Fixtures.sol";

import { DoubleEndedQueue, ProtocolAction, PendingAction } from "src/libraries/DoubleEndedQueue.sol";

/**
 * @custom:feature Test functions in `DoubleEndedQueue`
 * @custom:background Given the deque has 3 elements
 */
contract TestDequePopulated is DequeFixture {
    PendingAction public action1 = PendingAction(ProtocolAction.InitiateWithdrawal, 69, USER_1, 0, 1 ether);
    PendingAction public action2 = PendingAction(ProtocolAction.InitiateDeposit, 420, USER_1, -42, 1000 ether);
    PendingAction public action3 = PendingAction(ProtocolAction.InitiateOpenPosition, 42, USER_1, 0, 10);
    uint128 public rawIndex1;
    uint128 public rawIndex2;
    uint128 public rawIndex3;

    function setUp() public override {
        super.setUp();

        rawIndex2 = handler.pushBack(action2);
        rawIndex1 = handler.pushFront(action1);
        rawIndex3 = handler.pushBack(action3);
    }

    /**
     * @custom:scenario View functions should handle populated list fine
     * @custom:when Calling `empty` and `length`
     * @custom:then Returns `false` and `3`
     */
    function test_view() public {
        assertEq(handler.empty(), false, "empty");
        assertEq(handler.length(), 3, "length");
    }

    /**
     * @custom:scenario Accessing the front item
     * @custom:when Calling `front`
     * @custom:then Returns the front item
     */
    function test_accessFront() public {
        PendingAction memory front = handler.front();
        _assertActionsEqual(front, action1, "front");
    }

    /**
     * @custom:scenario Accessing the back item
     * @custom:when Calling `back`
     * @custom:then Returns the back item
     */
    function test_accessBack() public {
        PendingAction memory back = handler.back();
        _assertActionsEqual(back, action3, "back");
    }

    /**
     * @custom:scenario Accessing items at a given index
     * @custom:when Calling `at` with one of the indices
     * @custom:then Returns the item at the given index
     */
    function test_accessAt() public {
        _assertActionsEqual(handler.at(0), action1, "action 1");
        _assertActionsEqual(handler.at(1), action2, "action 2");
        _assertActionsEqual(handler.at(2), action3, "action 3");
    }

    /**
     * @custom:scenario Accessing items at a given raw index
     * @custom:when Calling `atRaw` with one of the raw indices
     * @custom:then Returns the item at the given raw index
     */
    function test_accessAtRaw() public {
        _assertActionsEqual(handler.atRaw(rawIndex1), action1, "action 1");
        _assertActionsEqual(handler.atRaw(rawIndex2), action2, "action 2");
        _assertActionsEqual(handler.atRaw(rawIndex3), action3, "action 3");
    }

    /**
     * @custom:scenario Accessing items at a given index
     * @custom:given The index is out of bounds
     * @custom:when Calling `at` with an out of bounds index
     * @custom:then It should revert with `QueueOutOfBounds`
     */
    function test_RevertWhen_OOB() public {
        vm.expectRevert(DoubleEndedQueue.QueueOutOfBounds.selector);
        handler.at(3);
        vm.expectRevert(DoubleEndedQueue.QueueOutOfBounds.selector);
        handler.atRaw(3);
    }

    /**
     * @custom:scenario Pushing an item to the front of the queue
     * @custom:when Calling `pushFront` with an item
     * @custom:then The length should increase by 1
     * @custom:and The item should be inserted at the front and gettable with `front` or its (raw) index
     * @custom:and The indices of the other items should be shifted one up
     * @custom:and The raw indices of the other items should not change
     */
    function test_pushFront() public {
        PendingAction memory action = PendingAction(ProtocolAction.InitiateClosePosition, 1, USER_1, 1, 1);
        uint128 rawIndex = handler.pushFront(action);
        uint128 expectedRawIndex;
        unchecked {
            expectedRawIndex = rawIndex1 - 1;
        }
        assertEq(rawIndex, expectedRawIndex);
        assertEq(handler.length(), 4);
        _assertActionsEqual(handler.front(), action, "front");
        _assertActionsEqual(handler.at(0), action, "at 0");
        _assertActionsEqual(handler.atRaw(rawIndex), action, "at raw index");
        _assertActionsEqual(handler.at(1), action1, "at 1");
        _assertActionsEqual(handler.atRaw(rawIndex1), action1, "at raw index 1");
        _assertActionsEqual(handler.at(2), action2, "at 2");
        _assertActionsEqual(handler.atRaw(rawIndex2), action2, "at raw index 2");
        _assertActionsEqual(handler.at(3), action3, "at 3");
        _assertActionsEqual(handler.atRaw(rawIndex3), action3, "at raw index 3");
    }

    /**
     * @custom:scenario Pushing an item to the back of the queue
     * @custom:when Calling `pushBack` with an item
     * @custom:then The length should increase by 1
     * @custom:and The item should be inserted at the back and gettable with `back` or its (raw) index
     * @custom:and The indices of the other items should not change
     * @custom:and The raw indices of the other items should not change
     */
    function test_pushBack() public {
        PendingAction memory action = PendingAction(ProtocolAction.InitiateClosePosition, 1, USER_1, 1, 1);
        uint128 rawIndex = handler.pushBack(action);
        uint128 expectedRawIndex;
        unchecked {
            expectedRawIndex = rawIndex3 + 1;
        }
        assertEq(rawIndex, expectedRawIndex);
        assertEq(handler.length(), 4);
        _assertActionsEqual(handler.back(), action, "back");
        _assertActionsEqual(handler.at(3), action, "at 3");
        _assertActionsEqual(handler.atRaw(rawIndex), action, "at raw index");
        _assertActionsEqual(handler.at(0), action1, "at 0");
        _assertActionsEqual(handler.atRaw(rawIndex1), action1, "at raw index 1");
        _assertActionsEqual(handler.at(1), action2, "at 1");
        _assertActionsEqual(handler.atRaw(rawIndex2), action2, "at raw index 2");
        _assertActionsEqual(handler.at(2), action3, "at 2");
        _assertActionsEqual(handler.atRaw(rawIndex3), action3, "at raw index 3");
    }

    /**
     * @custom:scenario Popping an item from the front of the queue
     * @custom:when Calling `popFront`
     * @custom:then The length should decrease by 1
     * @custom:and The correct item should be returned
     * @custom:and The indices of the other items should be shifted one down
     * @custom:and The raw indices of the other items should not change
     */
    function test_popFront() public {
        PendingAction memory action = handler.popFront();
        assertEq(handler.length(), 2);
        _assertActionsEqual(action, action1, "action 1");
        _assertActionsEqual(handler.at(0), action2, "at 0");
        _assertActionsEqual(handler.atRaw(rawIndex2), action2, "at raw index 2");
        _assertActionsEqual(handler.at(1), action3, "at 1");
        _assertActionsEqual(handler.atRaw(rawIndex3), action3, "at raw index 3");
    }

    /**
     * @custom:scenario Popping an item from the back of the queue
     * @custom:when Calling `popBack`
     * @custom:then The length should decrease by 1
     * @custom:and The correct item should be returned
     * @custom:and The indices of the other items should not change
     * @custom:and The raw indices of the other items should not change
     */
    function test_popBack() public {
        PendingAction memory action = handler.popBack();
        assertEq(handler.length(), 2);
        _assertActionsEqual(action, action3, "action 3");
        _assertActionsEqual(handler.at(0), action1, "at 0");
        _assertActionsEqual(handler.atRaw(rawIndex1), action1, "at raw index 1");
        _assertActionsEqual(handler.at(1), action2, "at 1");
        _assertActionsEqual(handler.atRaw(rawIndex2), action2, "at raw index 2");
    }

    /**
     * @custom:scenario Clearing the item at the front of the queue
     * @custom:when Calling `clearAt` with the raw index of the front item
     * @custom:then The length should decrease by 1
     * @custom:and The indices of the other items should be shifted one down
     * @custom:and The raw indices of the other items should not change
     */
    function test_clearAtFront() public {
        handler.clearAt(rawIndex1); // does a popFront
        assertEq(handler.length(), 2);
        _assertActionsEqual(handler.at(0), action2, "at 0");
        _assertActionsEqual(handler.atRaw(rawIndex2), action2, "at raw index 2");
        _assertActionsEqual(handler.at(1), action3, "at 1");
        _assertActionsEqual(handler.atRaw(rawIndex3), action3, "at raw index 3");
    }

    /**
     * @custom:scenario Clearing the item at the back of the queue
     * @custom:when Calling `clearAt` with the raw index of the back item
     * @custom:then The length should decrease by 1
     * @custom:and The indices of the other items should not change
     * @custom:and The raw indices of the other items should not change
     */
    function test_clearAtBack() public {
        handler.clearAt(rawIndex3); // does a popBack
        assertEq(handler.length(), 2);
        _assertActionsEqual(handler.at(0), action1, "at 0");
        _assertActionsEqual(handler.atRaw(rawIndex1), action1, "at raw index 1");
        _assertActionsEqual(handler.at(1), action2, "at 1");
        _assertActionsEqual(handler.atRaw(rawIndex2), action2, "at raw index 2");
    }

    /**
     * @custom:scenario Clearing an item at the middle of the queue
     * @custom:when Calling `clearAt` with the raw index of a middle item
     * @custom:then The length should not change
     * @custom:and The indices of the other items should not change
     * @custom:and The raw indices of the other items should not change
     * @custom:and The item should be reset to zero values
     */
    function test_clearAtMiddle() public {
        handler.clearAt(rawIndex2);
        assertEq(handler.length(), 3);
        _assertActionsEqual(handler.at(0), action1, "at 0");
        _assertActionsEqual(handler.atRaw(rawIndex1), action1, "at raw index 1");
        _assertActionsEqual(handler.at(2), action3, "at 2");
        _assertActionsEqual(handler.atRaw(rawIndex3), action3, "at raw index 3");
        PendingAction memory clearedAction = handler.at(1);
        assertTrue(clearedAction.action == ProtocolAction.None);
        assertEq(clearedAction.timestamp, 0);
        assertEq(clearedAction.user, address(0));
        assertEq(clearedAction.tick, 0);
        assertEq(clearedAction.amountOrIndex, 0);
    }

    /**
     * @custom:scenario Clearing all items in the queue
     * @custom:when Calling `clearAt` with the raw index of each item
     * @custom:then The length should decrease to 0
     * @custom:and The queue should be empty
     */
    function test_clearAll() public {
        handler.clearAt(rawIndex1);
        handler.clearAt(rawIndex2);
        handler.clearAt(rawIndex3);
        assertEq(handler.length(), 0);
        assertTrue(handler.empty());
    }
}

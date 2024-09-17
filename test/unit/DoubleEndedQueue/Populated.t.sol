// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { USER_1, USER_2 } from "../../utils/Constants.sol";
import { DequeFixture } from "./utils/Fixtures.sol";

import { IUsdnProtocolTypes as Types } from "../../../src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import { DoubleEndedQueue } from "../../../src/libraries/DoubleEndedQueue.sol";

/**
 * @custom:feature Test functions in `DoubleEndedQueue`
 * @custom:background Given the deque has 3 elements
 */
contract TestDequePopulated is DequeFixture {
    using DoubleEndedQueue for DoubleEndedQueue.Deque;

    DoubleEndedQueue.Deque internal queue;

    Types.PendingAction internal action1 = Types.PendingAction(
        Types.ProtocolAction.ValidateWithdrawal,
        69,
        200,
        USER_1,
        USER_2,
        0,
        1,
        1 ether,
        2 ether,
        12 ether,
        3 ether,
        4 ether,
        42_000 ether
    );
    Types.PendingAction internal action2 = Types.PendingAction(
        Types.ProtocolAction.ValidateDeposit,
        420,
        150,
        USER_1,
        USER_2,
        1,
        -42,
        1000 ether,
        2000 ether,
        120 ether,
        30 ether,
        40 ether,
        420_000 ether
    );
    Types.PendingAction internal action3 =
        Types.PendingAction(Types.ProtocolAction.ValidateOpenPosition, 42, 100, USER_1, USER_2, 0, 1, 10, 0, 0, 0, 0, 0);
    uint128 internal rawIndex1;
    uint128 internal rawIndex2;
    uint128 internal rawIndex3;

    function setUp() public override {
        super.setUp();

        rawIndex2 = queue.pushBack(action2);
        rawIndex1 = queue.pushFront(action1);
        rawIndex3 = queue.pushBack(action3);
    }

    /**
     * @custom:scenario View functions should handle populated list fine
     * @custom:when Calling `empty` and `length`
     * @custom:then Returns `false` and `3`
     */
    function test_view() public view {
        assertEq(queue.empty(), false, "empty");
        assertEq(queue.length(), 3, "length");
    }

    /**
     * @custom:scenario Accessing the front item
     * @custom:when Calling `front`
     * @custom:then Returns the front item
     */
    function test_accessFront() public view {
        (Types.PendingAction memory front, uint128 rawIndex) = queue.front();
        _assertActionsEqual(front, action1, "front");
        assertEq(rawIndex, rawIndex1, "raw index");
    }

    /**
     * @custom:scenario Accessing the back item
     * @custom:when Calling `back`
     * @custom:then Returns the back item
     */
    function test_accessBack() public view {
        (Types.PendingAction memory back, uint128 rawIndex) = queue.back();
        _assertActionsEqual(back, action3, "back");
        assertEq(rawIndex, rawIndex3, "raw index");
    }

    /**
     * @custom:scenario Accessing items at a given index
     * @custom:when Calling `at` with one of the indices
     * @custom:then Returns the item at the given index
     */
    function test_accessAt() public view {
        (Types.PendingAction memory at, uint128 rawIndex) = queue.at(0);
        _assertActionsEqual(at, action1, "action 1");
        assertEq(rawIndex, rawIndex1, "raw index 1");
        (at, rawIndex) = queue.at(1);
        _assertActionsEqual(at, action2, "action 2");
        assertEq(rawIndex, rawIndex2, "raw index 2");
        (at, rawIndex) = queue.at(2);
        _assertActionsEqual(at, action3, "action 3");
        assertEq(rawIndex, rawIndex3, "raw index 3");
    }

    /**
     * @custom:scenario Accessing items at a given raw index
     * @custom:when Calling `atRaw` with one of the raw indices
     * @custom:then Returns the item at the given raw index
     */
    function test_accessAtRaw() public view {
        assertTrue(queue.isValid(rawIndex1));
        assertTrue(queue.isValid(rawIndex2));
        assertTrue(queue.isValid(rawIndex3));
        _assertActionsEqual(queue.atRaw(rawIndex1), action1, "action 1");
        _assertActionsEqual(queue.atRaw(rawIndex2), action2, "action 2");
        _assertActionsEqual(queue.atRaw(rawIndex3), action3, "action 3");
    }

    /**
     * @custom:scenario Accessing items at a given index
     * @custom:given The index is out of bounds
     * @custom:when Calling `at` with an out of bounds index
     * @custom:then It should revert with `QueueOutOfBounds`
     */
    function test_RevertWhen_OOB() public {
        vm.expectRevert(DoubleEndedQueue.QueueOutOfBounds.selector);
        queue.at(3);
        vm.expectRevert(DoubleEndedQueue.QueueOutOfBounds.selector);
        queue.atRaw(3);
        assertFalse(queue.isValid(3));
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
        Types.PendingAction memory action = Types.PendingAction(
            Types.ProtocolAction.ValidateClosePosition, 1, 1, USER_1, USER_2, 1, 1, 1, 1, 1, 1, 1, 1
        );
        uint128 rawIndex = queue.pushFront(action);
        uint128 expectedRawIndex;
        unchecked {
            expectedRawIndex = rawIndex1 - 1;
        }
        assertEq(rawIndex, expectedRawIndex);
        assertEq(queue.length(), 4);
        (Types.PendingAction memory front,) = queue.front();
        _assertActionsEqual(front, action, "front");
        (Types.PendingAction memory at,) = queue.at(0);
        _assertActionsEqual(at, action, "at 0");
        _assertActionsEqual(queue.atRaw(rawIndex), action, "at raw index");
        (at,) = queue.at(1);
        _assertActionsEqual(at, action1, "at 1");
        _assertActionsEqual(queue.atRaw(rawIndex1), action1, "at raw index 1");
        (at,) = queue.at(2);
        _assertActionsEqual(at, action2, "at 2");
        _assertActionsEqual(queue.atRaw(rawIndex2), action2, "at raw index 2");
        (at,) = queue.at(3);
        _assertActionsEqual(at, action3, "at 3");
        _assertActionsEqual(queue.atRaw(rawIndex3), action3, "at raw index 3");
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
        Types.PendingAction memory action = Types.PendingAction(
            Types.ProtocolAction.ValidateClosePosition, 1, 1, USER_1, USER_2, 1, 1, 1, 1, 1, 1, 1, 1
        );
        uint128 rawIndex = queue.pushBack(action);
        uint128 expectedRawIndex;
        unchecked {
            expectedRawIndex = rawIndex3 + 1;
        }
        assertEq(rawIndex, expectedRawIndex);
        assertEq(queue.length(), 4);
        (Types.PendingAction memory back,) = queue.back();
        _assertActionsEqual(back, action, "back");
        (Types.PendingAction memory at,) = queue.at(3);
        _assertActionsEqual(at, action, "at 3");
        _assertActionsEqual(queue.atRaw(rawIndex), action, "at raw index");
        (at,) = queue.at(0);
        _assertActionsEqual(at, action1, "at 0");
        _assertActionsEqual(queue.atRaw(rawIndex1), action1, "at raw index 1");
        (at,) = queue.at(1);
        _assertActionsEqual(at, action2, "at 1");
        _assertActionsEqual(queue.atRaw(rawIndex2), action2, "at raw index 2");
        (at,) = queue.at(2);
        _assertActionsEqual(at, action3, "at 2");
        _assertActionsEqual(queue.atRaw(rawIndex3), action3, "at raw index 3");
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
        Types.PendingAction memory action = queue.popFront();
        assertEq(queue.length(), 2);
        _assertActionsEqual(action, action1, "action 1");
        (Types.PendingAction memory at,) = queue.at(0);
        _assertActionsEqual(at, action2, "at 0");
        _assertActionsEqual(queue.atRaw(rawIndex2), action2, "at raw index 2");
        (at,) = queue.at(1);
        _assertActionsEqual(at, action3, "at 1");
        _assertActionsEqual(queue.atRaw(rawIndex3), action3, "at raw index 3");
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
        Types.PendingAction memory action = queue.popBack();
        assertEq(queue.length(), 2);
        _assertActionsEqual(action, action3, "action 3");
        (Types.PendingAction memory at,) = queue.at(0);
        _assertActionsEqual(at, action1, "at 0");
        _assertActionsEqual(queue.atRaw(rawIndex1), action1, "at raw index 1");
        (at,) = queue.at(1);
        _assertActionsEqual(at, action2, "at 1");
        _assertActionsEqual(queue.atRaw(rawIndex2), action2, "at raw index 2");
    }

    /**
     * @custom:scenario Clearing the item at the front of the queue
     * @custom:when Calling `clearAt` with the raw index of the front item
     * @custom:then The length should decrease by 1
     * @custom:and The indices of the other items should be shifted one down
     * @custom:and The raw indices of the other items should not change
     */
    function test_clearAtFront() public {
        queue.clearAt(rawIndex1); // does a popFront
        assertEq(queue.length(), 2);
        (Types.PendingAction memory at,) = queue.at(0);
        _assertActionsEqual(at, action2, "at 0");
        _assertActionsEqual(queue.atRaw(rawIndex2), action2, "at raw index 2");
        (at,) = queue.at(1);
        _assertActionsEqual(at, action3, "at 1");
        _assertActionsEqual(queue.atRaw(rawIndex3), action3, "at raw index 3");
    }

    /**
     * @custom:scenario Clearing the item at the back of the queue
     * @custom:when Calling `clearAt` with the raw index of the back item
     * @custom:then The length should decrease by 1
     * @custom:and The indices of the other items should not change
     * @custom:and The raw indices of the other items should not change
     */
    function test_clearAtBack() public {
        queue.clearAt(rawIndex3); // does a popBack
        assertEq(queue.length(), 2);
        (Types.PendingAction memory at,) = queue.at(0);
        _assertActionsEqual(at, action1, "at 0");
        _assertActionsEqual(queue.atRaw(rawIndex1), action1, "at raw index 1");
        (at,) = queue.at(1);
        _assertActionsEqual(at, action2, "at 1");
        _assertActionsEqual(queue.atRaw(rawIndex2), action2, "at raw index 2");
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
        queue.clearAt(rawIndex2);
        assertEq(queue.length(), 3);
        (Types.PendingAction memory at,) = queue.at(0);
        _assertActionsEqual(at, action1, "at 0");
        _assertActionsEqual(queue.atRaw(rawIndex1), action1, "at raw index 1");
        (at,) = queue.at(2);
        _assertActionsEqual(at, action3, "at 2");
        _assertActionsEqual(queue.atRaw(rawIndex3), action3, "at raw index 3");
        (Types.PendingAction memory clearedAction,) = queue.at(1);
        Types.PendingAction memory empty;
        _assertActionsEqual(empty, clearedAction, "cleared action");
    }

    /**
     * @custom:scenario Clearing all items in the queue
     * @custom:when Calling `clearAt` with the raw index of each item
     * @custom:then The length should decrease to 0
     * @custom:and The queue should be empty
     */
    function test_clearAll() public {
        queue.clearAt(rawIndex1);
        queue.clearAt(rawIndex2);
        queue.clearAt(rawIndex3);
        assertEq(queue.length(), 0);
        assertTrue(queue.empty());
    }

    /**
     * @custom:scenario Checking if a raw index is valid
     * @custom:when Calling `isValid` with a random raw index
     * @custom:then Returns `true` if the index is valid, `false` otherwise
     * @param rawIndex The raw index to check
     */
    function testFuzz_isValid(uint128 rawIndex) public view {
        bool valid = queue.isValid(rawIndex);
        if (rawIndex == rawIndex1 || rawIndex == rawIndex2 || rawIndex == rawIndex3) {
            assertTrue(valid);
        } else {
            assertFalse(valid);
        }
    }
}

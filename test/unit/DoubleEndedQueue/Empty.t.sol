// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { DequeFixture } from "./utils/Fixtures.sol";

import { DoubleEndedQueue } from "../../../src/libraries/DoubleEndedQueue.sol";

/**
 * @custom:feature Test functions in `DoubleEndedQueue`
 * @custom:background Given the deque is empty
 */
contract TestDequeEmpty is DequeFixture {
    using DoubleEndedQueue for DoubleEndedQueue.Deque;

    DoubleEndedQueue.Deque internal queue;

    function setUp() public override {
        super.setUp();
    }

    /**
     * @custom:scenario View functions should handle empty list fine
     * @custom:when Calling `empty` and `length`
     * @custom:then Returns `true` and `0`
     */
    function test_view() public view {
        assertEq(queue.empty(), true, "empty");
        assertEq(queue.length(), 0, "length");
    }

    /**
     * @custom:scenario Popping and accessing items should revert
     * @custom:when Popping or accessing items in an empty list
     * @custom:then It should revert with `QueueEmpty` or `QueueOutOfBounds`
     */
    function test_RevertWhen_access() public {
        vm.expectRevert(DoubleEndedQueue.QueueEmpty.selector);
        queue.popBack();
        vm.expectRevert(DoubleEndedQueue.QueueEmpty.selector);
        queue.popFront();
        vm.expectRevert(DoubleEndedQueue.QueueEmpty.selector);
        queue.back();
        vm.expectRevert(DoubleEndedQueue.QueueEmpty.selector);
        queue.front();
        vm.expectRevert(DoubleEndedQueue.QueueOutOfBounds.selector);
        queue.at(0);
        vm.expectRevert(DoubleEndedQueue.QueueOutOfBounds.selector);
        queue.atRaw(0);
    }
}

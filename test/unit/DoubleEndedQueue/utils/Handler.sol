// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { IUsdnProtocolTypes as Types } from "../../../../src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import { DoubleEndedQueue } from "../../../../src/libraries/DoubleEndedQueue.sol";

/**
 * @title DequeHandler
 * @dev Wrapper to get gas usage report and coverage report.
 * Note that having `using DoubleEndedQueue for DoubleEndedQueue.Deque` and calling `queue.something()` does not make
 * the calls appear in coverage report.
 */
contract DequeHandler {
    DoubleEndedQueue.Deque public queue;

    function pushBack(Types.PendingAction memory value) public returns (uint128) {
        return DoubleEndedQueue.pushBack(queue, value);
    }

    function popBack() public returns (Types.PendingAction memory) {
        return DoubleEndedQueue.popBack(queue);
    }

    function pushFront(Types.PendingAction memory value) public returns (uint128) {
        return DoubleEndedQueue.pushFront(queue, value);
    }

    function popFront() public returns (Types.PendingAction memory) {
        return DoubleEndedQueue.popFront(queue);
    }

    function front() public view returns (Types.PendingAction memory, uint128) {
        return DoubleEndedQueue.front(queue);
    }

    function back() public view returns (Types.PendingAction memory, uint128) {
        return DoubleEndedQueue.back(queue);
    }

    function at(uint256 index) public view returns (Types.PendingAction memory, uint128) {
        return DoubleEndedQueue.at(queue, index);
    }

    function atRaw(uint128 rawIndex) public view returns (Types.PendingAction memory) {
        return DoubleEndedQueue.atRaw(queue, rawIndex);
    }

    function clearAt(uint128 rawIndex) public {
        DoubleEndedQueue.clearAt(queue, rawIndex);
    }

    function length() public view returns (uint256) {
        return DoubleEndedQueue.length(queue);
    }

    function empty() public view returns (bool) {
        return DoubleEndedQueue.empty(queue);
    }
}

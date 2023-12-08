// SPDX-License-Identifier: MIT
// Based on the OpenZeppelin implementation
pragma solidity ^0.8.20;

import { ProtocolAction, PendingAction } from "src/interfaces/UsdnProtocol/IUsdnProtocol.sol";

/**
 * @dev A sequence of items with the ability to efficiently push and pop items (i.e. insert and remove) on both ends of
 * the sequence (called front and back). Among other access patterns, it can be used to implement efficient LIFO and
 * FIFO queues. Storage use is optimized, and all operations are O(1) constant time. This includes {clear}, given that
 * the existing queue contents are left in storage.
 *
 * The struct is called `Deque` and holds `PendingAction`s. This data structure can only be used in storage, and not in
 * memory.
 *
 * ```solidity
 * DoubleEndedQueue.Deque queue;
 * ```
 */
library DoubleEndedQueue {
    /**
     * @dev An operation (e.g. {front}) couldn't be completed due to the queue being empty.
     */
    error QueueEmpty();

    /**
     * @dev A push operation couldn't be completed due to the queue being full.
     */
    error QueueFull();

    /**
     * @dev An operation (e.g. {at}) couldn't be completed due to an index being out of bounds.
     */
    error QueueOutOfBounds();

    /**
     * @dev Indices are 128 bits so begin and end are packed in a single storage slot for efficient access.
     *
     * Struct members have an underscore prefix indicating that they are "private" and should not be read or written to
     * directly. Use the functions provided below instead. Modifying the struct manually may violate assumptions and
     * lead to unexpected behavior.
     *
     * The first item is at data[begin] and the last item is at data[end - 1]. This range can wrap around.
     */
    struct Deque {
        uint128 _begin;
        uint128 _end;
        mapping(uint128 index => PendingAction) _data;
    }

    /**
     * @dev Inserts an item at the end of the queue.
     *
     * Reverts with {QueueFull} if the queue is full.
     */
    function pushBack(Deque storage deque, PendingAction memory value) internal returns (uint128 backIndex_) {
        unchecked {
            backIndex_ = deque._end;
            if (backIndex_ + 1 == deque._begin) revert QueueFull();
            deque._data[backIndex_] = value;
            deque._end = backIndex_ + 1;
        }
    }

    /**
     * @dev Removes the item at the end of the queue and returns it.
     *
     * Reverts with {QueueEmpty} if the queue is empty.
     */
    function popBack(Deque storage deque) internal returns (PendingAction memory value_) {
        unchecked {
            uint128 backIndex = deque._end;
            if (backIndex == deque._begin) revert QueueEmpty();
            --backIndex;
            value_ = deque._data[backIndex];
            delete deque._data[backIndex];
            deque._end = backIndex;
        }
    }

    /**
     * @dev Inserts an item at the beginning of the queue.
     *
     * Reverts with {QueueFull} if the queue is full.
     */
    function pushFront(Deque storage deque, PendingAction memory value) internal {
        unchecked {
            uint128 frontIndex = deque._begin - 1;
            if (frontIndex == deque._end) revert QueueFull();
            deque._data[frontIndex] = value;
            deque._begin = frontIndex;
        }
    }

    /**
     * @dev Removes the item at the beginning of the queue and returns it.
     *
     * Reverts with `QueueEmpty` if the queue is empty.
     */
    function popFront(Deque storage deque) internal returns (PendingAction memory value_) {
        unchecked {
            uint128 frontIndex = deque._begin;
            if (frontIndex == deque._end) revert QueueEmpty();
            value_ = deque._data[frontIndex];
            delete deque._data[frontIndex];
            deque._begin = frontIndex + 1;
        }
    }

    /**
     * @dev Returns the item at the beginning of the queue.
     *
     * Reverts with `QueueEmpty` if the queue is empty.
     */
    function front(Deque storage deque) internal view returns (PendingAction memory value_) {
        if (empty(deque)) revert QueueEmpty();
        value_ = deque._data[deque._begin];
    }

    /**
     * @dev Returns the item at the end of the queue.
     *
     * Reverts with `QueueEmpty` if the queue is empty.
     */
    function back(Deque storage deque) internal view returns (PendingAction memory value_) {
        if (empty(deque)) revert QueueEmpty();
        unchecked {
            value_ = deque._data[deque._end - 1];
        }
    }

    /**
     * @dev Return the item at a position in the queue given by `index`, with the first item at 0 and last item at
     * `length(deque) - 1`.
     *
     * Reverts with `QueueOutOfBounds` if the index is out of bounds.
     */
    function at(Deque storage deque, uint256 index) internal view returns (PendingAction memory value_) {
        if (index >= length(deque)) revert QueueOutOfBounds();
        // By construction, length is a uint128, so the check above ensures that index can be safely downcast to uint128
        unchecked {
            value_ = deque._data[deque._begin + uint128(index)];
        }
    }

    /**
     * @dev Return the item at a position in the queue given by `rawIndex`, indexing into the underlying storage array
     * directly.
     *
     * Reverts with `QueueOutOfBounds` if the index is out of bounds.
     */
    function atRaw(Deque storage deque, uint128 rawIndex) internal view returns (PendingAction memory value_) {
        if (deque._begin > deque._end) {
            // here the values are split at the beginning and end of the range, so invalid indices are in the middle
            if (rawIndex < deque._begin && rawIndex >= deque._end) revert QueueOutOfBounds();
        } else if (rawIndex < deque._begin || rawIndex >= deque._end) {
            revert QueueOutOfBounds();
        }
        value_ = deque._data[rawIndex];
    }

    /**
     * @dev Deletes the item at a position in the queue given by `rawIndex`, indexing into the underlying storage array
     * directly. If clearing the front or back item, then the bounds are updated. Otherwise, the values are simply set
     * to zero and the queue's begin and end indices are not updated.
     */
    function clearAt(Deque storage deque, uint128 rawIndex) internal {
        uint128 backIndex = deque._end;
        unchecked {
            backIndex--;
        }
        if (rawIndex == deque._begin) popFront(deque);
        else if (rawIndex == backIndex) popBack(deque);
        else delete deque._data[rawIndex];
    }

    /**
     * @dev Returns the number of items in the queue.
     */
    function length(Deque storage deque) internal view returns (uint256) {
        unchecked {
            return uint256(deque._end - deque._begin);
        }
    }

    /**
     * @dev Returns true if the queue is empty.
     */
    function empty(Deque storage deque) internal view returns (bool) {
        return deque._end == deque._begin;
    }
}

// SPDX-License-Identifier: MIT
// based on the OpenZeppelin implementation
pragma solidity ^0.8.20;

import { IUsdnProtocolTypes as Types } from "../interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";

/**
 * @notice A sequence of items with the ability to efficiently push and pop items (i.e. insert and remove) on both ends
 * of the sequence (called front and back)
 * @dev Storage use is optimized, and all operations are O(1) constant time
 *
 * The struct is called `Deque` and holds `PendingAction`s. This data structure can only be used in storage, and not in
 * memory
 */
library DoubleEndedQueue {
    /// @dev Indicates that an operation (e.g. {front}) couldn't be completed due to the queue being empty
    error QueueEmpty();

    /// @dev Indicates that a push operation couldn't be completed due to the queue being full
    error QueueFull();

    /// @dev Indicates that an operation (e.g. {atRaw}) couldn't be completed due to an index being out of bounds
    error QueueOutOfBounds();

    /**
     * @dev Indices are 128 bits so begin and end are packed in a single storage slot for efficient access
     *
     * Struct members have an underscore prefix indicating that they are "private" and should not be read or written to
     * directly. Use the functions provided below instead. Modifying the struct manually may violate assumptions and
     * lead to unexpected behavior
     *
     * The first item is at data[begin] and the last item is at data[end - 1]. This range can wrap around
     * @param _begin The index of the first item in the queue
     * @param _end The index of the item after the last item in the queue
     * @param _data The items in the queue
     */
    struct Deque {
        uint128 _begin;
        uint128 _end;
        mapping(uint128 index => Types.PendingAction) _data;
    }

    /**
     * @dev Inserts an item at the end of the queue
     * Reverts with {QueueFull} if the queue is full
     * @param deque The queue
     * @param value The item to insert
     * @return backIndex_ The raw index of the inserted item
     */
    function pushBack(Deque storage deque, Types.PendingAction memory value) external returns (uint128 backIndex_) {
        unchecked {
            backIndex_ = deque._end;
            if (backIndex_ + 1 == deque._begin) {
                revert QueueFull();
            }
            deque._data[backIndex_] = value;
            deque._end = backIndex_ + 1;
        }
    }

    /**
     * @dev Removes the item at the end of the queue and returns it
     * Reverts with {QueueEmpty} if the queue is empty
     * @param deque The queue
     * @return value_ The removed item
     */
    function popBack(Deque storage deque) public returns (Types.PendingAction memory value_) {
        unchecked {
            uint128 backIndex = deque._end;
            if (backIndex == deque._begin) {
                revert QueueEmpty();
            }
            --backIndex;
            value_ = deque._data[backIndex];
            delete deque._data[backIndex];
            deque._end = backIndex;
        }
    }

    /**
     * @dev Inserts an item at the beginning of the queue
     * Reverts with {QueueFull} if the queue is full
     * @param deque The queue
     * @param value The item to insert
     * @return frontIndex_ The raw index of the inserted item
     */
    function pushFront(Deque storage deque, Types.PendingAction memory value) external returns (uint128 frontIndex_) {
        unchecked {
            frontIndex_ = deque._begin - 1;
            if (frontIndex_ == deque._end) {
                revert QueueFull();
            }
            deque._data[frontIndex_] = value;
            deque._begin = frontIndex_;
        }
    }

    /**
     * @dev Removes the item at the beginning of the queue and returns it
     * Reverts with `QueueEmpty` if the queue is empty
     * @param deque The queue
     * @return value_ The removed item
     */
    function popFront(Deque storage deque) public returns (Types.PendingAction memory value_) {
        unchecked {
            uint128 frontIndex = deque._begin;
            if (frontIndex == deque._end) {
                revert QueueEmpty();
            }
            value_ = deque._data[frontIndex];
            delete deque._data[frontIndex];
            deque._begin = frontIndex + 1;
        }
    }

    /**
     * @dev Returns the item at the beginning of the queue
     * Reverts with `QueueEmpty` if the queue is empty
     * @param deque The queue
     * @return value_ The item at the front of the queue
     * @return rawIndex_ The raw index of the returned item
     */
    function front(Deque storage deque) external view returns (Types.PendingAction memory value_, uint128 rawIndex_) {
        if (empty(deque)) {
            revert QueueEmpty();
        }
        rawIndex_ = deque._begin;
        value_ = deque._data[rawIndex_];
    }

    /**
     * @dev Returns the item at the end of the queue
     * Reverts with `QueueEmpty` if the queue is empty
     * @param deque The queue
     * @return value_ The item at the back of the queue
     * @return rawIndex_ The raw index of the returned item
     */
    function back(Deque storage deque) external view returns (Types.PendingAction memory value_, uint128 rawIndex_) {
        if (empty(deque)) {
            revert QueueEmpty();
        }
        unchecked {
            rawIndex_ = deque._end - 1;
            value_ = deque._data[rawIndex_];
        }
    }

    /**
     * @dev Return the item at a position in the queue given by `index`, with the first item at 0 and the last item at
     * `length(deque) - 1`
     * Reverts with `QueueOutOfBounds` if the index is out of bounds
     * @param deque The queue
     * @param index The index of the item to return
     * @return value_ The item at the given index
     * @return rawIndex_ The raw index of the item
     */
    function at(Deque storage deque, uint256 index)
        external
        view
        returns (Types.PendingAction memory value_, uint128 rawIndex_)
    {
        if (index >= length(deque)) {
            revert QueueOutOfBounds();
        }
        // by construction, length is a uint128, so the check above ensures that
        // the index can be safely downcasted to a uint128
        unchecked {
            rawIndex_ = deque._begin + uint128(index);
            value_ = deque._data[rawIndex_];
        }
    }

    /**
     * @dev Return the item at a position in the queue given by `rawIndex`, indexing into the underlying storage array
     * directly
     * Reverts with `QueueOutOfBounds` if the index is out of bounds
     * @param deque The queue
     * @param rawIndex The index of the item to return
     * @return value_ The item at the given index
     */
    function atRaw(Deque storage deque, uint128 rawIndex) external view returns (Types.PendingAction memory value_) {
        if (deque._begin > deque._end) {
            // here the values are split at the beginning and end of the range, so invalid indices are in the middle
            if (rawIndex < deque._begin && rawIndex >= deque._end) {
                revert QueueOutOfBounds();
            }
        } else if (rawIndex < deque._begin || rawIndex >= deque._end) {
            revert QueueOutOfBounds();
        }
        value_ = deque._data[rawIndex];
    }

    /**
     * @dev Deletes the item at a position in the queue given by `rawIndex`, indexing into the underlying storage array
     * directly. If clearing the front or back item, then the bounds are updated. Otherwise, the values are simply set
     * to zero and the queue's begin and end indices are not updated
     * @param deque The queue
     * @param rawIndex The index of the item to delete
     */
    function clearAt(Deque storage deque, uint128 rawIndex) external {
        uint128 backIndex = deque._end;
        unchecked {
            backIndex--;
        }
        if (rawIndex == deque._begin) {
            popFront(deque); // reverts if empty
        } else if (rawIndex == backIndex) {
            popBack(deque); // reverts if empty
        } else {
            // we don't care to revert if this is not a valid index, since we're just clearing it
            delete deque._data[rawIndex];
        }
    }

    /**
     * @dev Check if the raw index is valid (in bounds)
     * @param deque The queue
     * @param rawIndex The index of the item to return
     * @return valid_ Whether the raw index is valid
     */
    function isValid(Deque storage deque, uint128 rawIndex) external view returns (bool valid_) {
        if (deque._begin > deque._end) {
            // here the values are split at the beginning and end of the range, so invalid indices are in the middle
            if (rawIndex < deque._begin && rawIndex >= deque._end) {
                return false;
            }
        } else if (rawIndex < deque._begin || rawIndex >= deque._end) {
            return false;
        }
        valid_ = true;
    }

    /**
     * @dev Returns the number of items in the queue
     * @param deque The queue
     * @return length_ The number of items in the queue
     */
    function length(Deque storage deque) public view returns (uint256 length_) {
        unchecked {
            length_ = uint256(deque._end - deque._begin);
        }
    }

    /**
     * @dev Returns true if the queue is empty
     * @param deque The queue
     * @return empty_ True if the queue is empty
     */
    function empty(Deque storage deque) internal view returns (bool empty_) {
        empty_ = deque._end == deque._begin;
    }
}

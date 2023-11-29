// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { LibBitmap } from "solady/src/utils/LibBitmap.sol";

contract BitmapHandler {
    using LibBitmap for LibBitmap.Bitmap;

    LibBitmap.Bitmap bitmap;

    function set(int24 tick) public {
        bitmap.set(_tickToBitmapIndex(tick));
    }

    function unset(int24 tick) public {
        bitmap.unset(_tickToBitmapIndex(tick));
    }

    function findLastSet(int24 start) public view returns (int24) {
        return _bitmapIndexToTick(bitmap.findLastSet(_tickToBitmapIndex(start)));
    }

    function _tickToBitmapIndex(int24 _tick) internal pure returns (uint256 index_) {
        // shift into positive and cast to uint256
        index_ = uint256(int256(_tick) - int256(type(int24).min));
    }

    /// @dev Convert a Bitmap index to a signed tick
    /// @param _index The index into the Bitmap
    /// @return tick_ The tick corresponding to the index, a multiple of `tickSpacing`
    function _bitmapIndexToTick(uint256 _index) internal pure returns (int24 tick_) {
        // cast to int256 and shift into negative
        tick_ = int24(int256(_index) + int256(type(int24).min));
    }
}

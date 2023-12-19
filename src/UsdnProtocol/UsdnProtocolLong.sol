// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import { LibBitmap } from "solady/src/utils/LibBitmap.sol";

import { Position } from "src/interfaces/UsdnProtocol/IUsdnProtocol.sol";
import { UsdnProtocolVault } from "src/UsdnProtocol/UsdnProtocolVault.sol";
import { TickMath } from "src/libraries/TickMath.sol";

abstract contract UsdnProtocolLong is UsdnProtocolVault {
    using LibBitmap for LibBitmap.Bitmap;

    function getLongPosition(int24 tick, uint256 index) public view returns (Position memory pos_) {
        pos_ = _longPositions[_tickHash(tick)][index];
    }

    function getLongPositionsLength(int24 tick) external view returns (uint256 len_) {
        len_ = _positionsInTick[_tickHash(tick)];
    }

    function findMaxInitializedTick(int24 searchStart) public view returns (int24 tick_) {
        uint256 index = _tickBitmap.findLastSet(_tickToBitmapIndex(searchStart));
        if (index == LibBitmap.NOT_FOUND) {
            tick_ = TickMath.minUsableTick(_tickSpacing);
        } else {
            tick_ = _bitmapIndexToTick(index);
        }
    }

    /**
     * @dev Convert a signed tick to an unsigned index into the Bitmap
     * @param tick The tick to convert, a multiple of `tickSpacing`
     * @return index_ The index into the Bitmap
     */
    function _tickToBitmapIndex(int24 tick) internal view returns (uint256 index_) {
        int24 compactTick = tick / _tickSpacing;
        // shift into positive and cast to uint256
        index_ = uint256(int256(compactTick) - int256(type(int24).min));
    }

    /**
     * @dev Convert a Bitmap index to a signed tick
     * @param index The index into the Bitmap
     * @return tick_ The tick corresponding to the index, a multiple of `tickSpacing`
     */
    function _bitmapIndexToTick(uint256 index) internal view returns (int24 tick_) {
        // cast to int256 and shift into negative
        int24 compactTick = int24(int256(index) + int256(type(int24).min));
        tick_ = compactTick * _tickSpacing;
    }

    function _tickHash(int24 tick) internal view returns (bytes32) {
        return keccak256(abi.encodePacked(tick, _tickVersion[tick]));
    }
}

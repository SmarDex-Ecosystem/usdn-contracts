// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { console2 } from "forge-std/Test.sol";

import { TickBitmap } from "test/unit/TickBitmapUniswap/libraries/TickBitmap.sol";

contract UniswapBitmapHandler {
    using TickBitmap for mapping(int16 => uint256);

    mapping(int16 => uint256) bitmap;

    function set(int24 idx) public {
        bitmap.flipTick(idx, 1);
    }

    function unset(int24 idx) public {
        bitmap.flipTick(idx, 1);
    }

    function findLastSet(int24 start) public view returns (int24) {
        int24 tick = start + 1;
        do {
            (int24 next, bool initialized) = bitmap.nextInitializedTickWithinOneWord(tick - 1, 1, true);
            tick = next;
            if (initialized) {
                break;
            }
        } while (true);
        return tick;
    }
}

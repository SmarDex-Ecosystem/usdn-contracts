// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.20;

import { Test } from "forge-std/Test.sol";

import { UniswapBitmapHandler } from "test/unit/TickBitmapUniswap/utils/Handler.sol";

/// @dev Test some functions of the library to check gas consumption
contract TestUniswapBitmap is Test {
    UniswapBitmapHandler bitmap;

    function setUp() public {
        bitmap = new UniswapBitmapHandler();
    }

    /// @dev Test set and unset functions
    function test_setUnset() public {
        for (int24 i; i < 100; ++i) {
            bitmap.set(i * 10);
        }
        for (int24 i = 100; i > 0; --i) {
            bitmap.unset(10 * (i - 1));
        }
    }

    /// @dev Test find function
    function test_find() public {
        bitmap.set(0);
        bitmap.set(10);
        bitmap.set(100);
        bitmap.set(1000);

        int24 res = bitmap.findLastSet(9);
        assertEq(res, 0);
        res = bitmap.findLastSet(99);
        assertEq(res, 10);
        res = bitmap.findLastSet(999);
        assertEq(res, 100);
    }
}

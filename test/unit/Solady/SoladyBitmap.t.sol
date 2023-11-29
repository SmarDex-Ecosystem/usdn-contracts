// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { Test } from "forge-std/Test.sol";

import { BitmapHandler } from "test/unit/Solady/utils/Handler.sol";

contract TestSoladyBitmap is Test {
    BitmapHandler bitmap;

    function setUp() public {
        bitmap = new BitmapHandler();
    }

    function test_setUnset() public {
        for (int24 i; i < 100; ++i) {
            bitmap.set(i * 10);
        }
        for (int24 i = 100; i > 0; --i) {
            bitmap.unset(10 * (i - 1));
        }
    }

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

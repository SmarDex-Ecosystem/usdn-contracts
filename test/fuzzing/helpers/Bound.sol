// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import { Test } from "forge-std/Test.sol";

contract Bound is Test {
    function int256Bound(uint256 value, int256 min, int256 max) public pure returns (int256) {
        uint256 diff = uint256(max - min);
        diff = bound(value, 0, diff);
        return min + int256(diff);
    }

    function doesOverflow(uint128 a, uint128 b) public returns (bool) {
        uint128 result;
        unchecked {
            result = a + b;
        }
        if (result < a) {
            return true;
        }
        return false;
    }
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import { Test } from "forge-std/Test.sol";

contract Bound is Test {
    function int256Bound(uint256 value, uint256 min, uint256 max) public pure returns (int256) {
        value = bound(value, 0, (max > min ? max : min));
        if (value % 2 == 0) {
            return int256(value);
        }
        return -int256(value);
    }
}

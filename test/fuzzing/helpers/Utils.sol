// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import { Test } from "forge-std/Test.sol";

contract Utils is Test {
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

    function mergeTwoArray(address[] memory a, address[] memory b)
        public
        pure
        returns (address[] memory filteredArray)
    {
        filteredArray = new address[](a.length + b.length);
        for (uint256 i = 0; i < b.length; i++) {
            filteredArray[i] = b[i];
        }
        for (uint256 i = 0; i < a.length; i++) {
            filteredArray[b.length + i] = a[i];
        }
    }
}

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

    function boundToIntCast(uint256 value) public returns (uint256) {
        uint256 uint255MaxValue = 2 ** 255 - 1;
        if (value > uint255MaxValue) {
            return value - uint255MaxValue;
        }
        return value;
    }

    function addressFromArraysFiltered(address[] memory a, address[] memory b, bool removeMsgSender, uint256 destRand)
        public
        view
        returns (address payable dest)
    {
        address[] memory filteredUsers;
        if (removeMsgSender) {
            filteredUsers = new address[](b.length - 1);
            uint256 index = 0;
            for (uint256 i = 0; i < b.length; i++) {
                if (b[i] != msg.sender) {
                    filteredUsers[index] = b[i];
                    index++;
                }
            }
        } else {
            filteredUsers = b;
        }

        address[] memory filteredArray = new address[](a.length + filteredUsers.length);
        for (uint256 i = 0; i < filteredUsers.length; i++) {
            filteredArray[i] = filteredUsers[i];
        }
        for (uint256 i = 0; i < a.length; i++) {
            filteredArray[filteredUsers.length + i] = a[i];
        }

        destRand = bound(destRand, 0, filteredArray.length - 1);
        dest = payable(filteredArray[destRand]);
    }
}

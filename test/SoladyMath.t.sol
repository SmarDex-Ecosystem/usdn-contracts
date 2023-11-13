// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { Test } from "forge-std/Test.sol";

import { FixedPointMathLib } from "solady/src/utils/FixedPointMathLib.sol";

contract TestTickMath is Test {
    function testFuzzExpWad(int256 value) public {
        value = bound(value, -42_139_678_854_452_767_552, 135_305_999_368_893_231_588);
        string[] memory cmds = new string[](3);
        cmds[0] = "./test_utils/target/release/test_utils";
        cmds[1] = "exp-wad";
        cmds[2] = vm.toString(value);
        bytes memory result = vm.ffi(cmds);
        int256 ref = abi.decode(result, (int256));
        int256 test = int256(FixedPointMathLib.expWad(value));
        assertApproxEqRel(ref, test, 1); // 0.0000000000000001%
    }
}

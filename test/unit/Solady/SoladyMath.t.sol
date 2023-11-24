// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { Test } from "forge-std/Test.sol";

import { FixedPointMathLib } from "solady/src/utils/FixedPointMathLib.sol";

import { TickMath } from "src/libraries/TickMath.sol";

/**
 * @custom:feature Solady math library fuzzing (diff testing)
 * @dev Test the Solady math library against a reference implementation in Rust using decimal-rs.
 *
 * The Rust implementation is in the test_utils folder/crate and should be compiled beforehand.
 *
 * Run the following command in the test_utils folder:
 *
 * ```bash
 * cargo build --release
 * ```
 *
 * We expect a small error in the math results due to the different precision of the two libraries, but it's in an
 * acceptable range (see comments in the tests below).
 *
 */
contract TestSoladyMath is Test {
    /**
     * @custom:scenario Fuzzing the `expWad` function
     * @custom:given A value between -42_139_678_854_452_767_552 and 135_305_999_368_893_231_588
     * @custom:when The `expWad` function is called with the value
     * @custom:then The result is equal to the result of the Rust implementation within 0.000000000000007%
     * @param value The input to `expWad`
     */
    function testFuzzFFIExpWad(int256 value) public {
        value = bound(value, -42_139_678_854_452_767_552, 135_305_999_368_893_231_588); // acceptable values for solady
        string[] memory cmds = new string[](3);
        cmds[0] = "./test_utils/target/release/test_utils";
        cmds[1] = "exp-wad";
        cmds[2] = vm.toString(value);
        bytes memory result = vm.ffi(cmds);
        int256 ref = abi.decode(result, (int256));
        int256 test = int256(FixedPointMathLib.expWad(value));
        assertApproxEqRel(ref, test, 70); // 0.000000000000007%
    }

    /**
     * @custom:scenario Fuzzing the `lnWad` function
     * @custom:given A value between `MIN_PRICE` and `MAX_PRICE` of `TickMath`
     * @custom:when The `lnWad` function is called with the value
     * @custom:then The result is equal to the result of the Rust implementation within 0.0000000000003%
     * @param value the input to `lnWad`
     */
    function testFuzzFFILnWad(uint256 value) public {
        value = bound(value, TickMath.MIN_PRICE, TickMath.MAX_PRICE);
        string[] memory cmds = new string[](3);
        cmds[0] = "./test_utils/target/release/test_utils";
        cmds[1] = "ln-wad";
        cmds[2] = vm.toString(value);
        bytes memory result = vm.ffi(cmds);
        int256 ref = abi.decode(result, (int256));
        int256 test = int256(FixedPointMathLib.lnWad(int256(value)));
        assertApproxEqRel(ref, test, 3000); // 0.0000000000003%
    }

    /**
     * @custom:scenario Fuzzing the `powWad` function
     * @custom:given A base of 1.0001
     * @custom:and An exponent between 500_000 and 900_000
     * @custom:when The `powWad` function is called with the base and exponent
     * @custom:then The result is equal to the result of the Rust implementation within 0.0000000001%
     * @param exp The exponent to raise the base to
     */
    function testFuzzFFIPowWad(int256 exp) public {
        int256 base = 1.0001 ether;
        exp = bound(exp, 500_000 ether, 900_000 ether);
        string[] memory cmds = new string[](4);
        cmds[0] = "./test_utils/target/release/test_utils";
        cmds[1] = "pow-wad";
        cmds[2] = vm.toString(base);
        cmds[3] = vm.toString(exp);
        bytes memory result = vm.ffi(cmds);
        int256 ref = abi.decode(result, (int256));
        int256 test = int256(FixedPointMathLib.powWad(base, exp));
        assertApproxEqRel(ref, test, 1_000_000); // 0.0000000001%
    }

    /**
     * @custom:scenario Fuzzing the `divUp` function
     * @custom:given A left hand side between 0 and 10^38
     * @custom:and A right hand side between 1 and 10^38
     * @custom:when The `divUp` function is called with the left hand side and right hand side
     * @custom:then The result is equal to the result of the Rust implementation
     * @param lhs the left hand side of the division
     * @param rhs the right hand side of the division
     */
    function testFuzzFFIDivUp(uint256 lhs, uint256 rhs) public {
        // rust implementation only has 38 digits left of decimal point max
        lhs = bound(lhs, 0, 10_000_000_000_000_000_000_000_000_000_000_000_000);
        rhs = bound(rhs, 1, 10_000_000_000_000_000_000_000_000_000_000_000_000);
        vm.assume(rhs != 0);
        string[] memory cmds = new string[](4);
        cmds[0] = "./test_utils/target/release/test_utils";
        cmds[1] = "div-up";
        cmds[2] = vm.toString(lhs);
        cmds[3] = vm.toString(rhs);
        bytes memory result = vm.ffi(cmds);
        uint256 ref = abi.decode(result, (uint256));
        uint256 test = FixedPointMathLib.divUp(lhs, rhs);
        assertEq(ref, test);
    }
}

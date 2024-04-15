// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { HugeIntFixture } from "test/unit/HugeInt/utils/Fixtures.sol";

import { HugeInt } from "src/libraries/HugeInt.sol";

/**
 * @custom:feature Fuzzing tests for the `HugeInt` uint512 library
 */
contract TestHugeIntFuzzing is HugeIntFixture {
    function setUp() public override {
        super.setUp();
    }

    /**
     * @custom:scenario Fuzzing the `add` function
     * @custom:given Two 512-bit unsigned integers
     * @custom:when The `add` function is called with the two integers
     * @custom:then The result is equal to the sum of the two integers
     * @param a0 least-significant bits of the first operand
     * @param a1 most-significant bits of the first operand
     * @param b0 least-significant bits of the second operand
     * @param b1 most-significant bits of the second operand
     */
    function testFuzz_FFIAdd(uint256 a0, uint256 a1, uint256 b0, uint256 b1) public {
        bytes memory a = abi.encodePacked(a1, a0);
        bytes memory b = abi.encodePacked(b1, b0);
        bytes memory result = vmFFIRustCommand("huge-int-add", vm.toString(a), vm.toString(b));
        (uint256 res0, uint256 res1) = abi.decode(result, (uint256, uint256));
        HugeInt.Uint512 memory res = handler.add(HugeInt.Uint512(a0, a1), HugeInt.Uint512(b0, b1));
        assertEq(res.lo, res0, "lo");
        assertEq(res.hi, res1, "hi");
    }

    /**
     * @custom:scenario Fuzzing the `sub` function
     * @custom:given Two 512-bit unsigned integers
     * @custom:when The `sub` function is called with the two integers
     * @custom:then The result is equal to the difference of the two integers
     * @param a0 least-significant bits of the first operand
     * @param a1 most-significant bits of the first operand
     * @param b0 least-significant bits of the second operand
     * @param b1 most-significant bits of the second operand
     */
    function testFuzz_FFISub(uint256 a0, uint256 a1, uint256 b0, uint256 b1) public {
        bytes memory a = abi.encodePacked(a1, a0);
        bytes memory b = abi.encodePacked(b1, b0);
        bytes memory result = vmFFIRustCommand("huge-int-sub", vm.toString(a), vm.toString(b));
        (uint256 res0, uint256 res1) = abi.decode(result, (uint256, uint256));
        HugeInt.Uint512 memory res = handler.sub(HugeInt.Uint512(a0, a1), HugeInt.Uint512(b0, b1));
        assertEq(res.lo, res0, "lo");
        assertEq(res.hi, res1, "hi");
    }

    /**
     * @custom:scenario Fuzzing the `mul256` function
     * @custom:given Two 256-bit unsigned integers
     * @custom:when The `mul256` function is called with the two integers
     * @custom:then The result is equal to the product of the two integers as a `Uint512`
     * @param a the first operand
     * @param b the second operand
     */
    function testFuzz_FFIMul256(uint256 a, uint256 b) public {
        bytes memory result = vmFFIRustCommand("huge-int-mul256", vm.toString(a), vm.toString(b));
        (uint256 res0, uint256 res1) = abi.decode(result, (uint256, uint256));
        HugeInt.Uint512 memory res = handler.mul(a, b);
        assertEq(res.lo, res0, "lo");
        assertEq(res.hi, res1, "hi");
    }

    /**
     * @custom:scenario Fuzzing the `mul` function
     * @custom:given Two 512-bit unsigned integers
     * @custom:when The `mul` function is called with the two integers
     * @custom:then The result is equal to the product of the two integers as a `Uint512`
     * @param a0 least-significant bits of the first operand
     * @param a1 most-significant bits of the first operand
     * @param b0 least-significant bits of the second operand
     * @param b1 most-significant bits of the second operand
     */
    function testFuzz_FFIMul(uint256 a0, uint256 a1, uint256 b0, uint256 b1) public {
        bytes memory a = abi.encodePacked(a1, a0);
        bytes memory b = abi.encodePacked(b1, b0);
        bytes memory result = vmFFIRustCommand("huge-int-mul", vm.toString(a), vm.toString(b));
        (uint256 res0, uint256 res1) = abi.decode(result, (uint256, uint256));
        HugeInt.Uint512 memory res = handler.mul(HugeInt.Uint512(a0, a1), HugeInt.Uint512(b0, b1));
        assertEq(res.lo, res0, "lo");
        assertEq(res.hi, res1, "hi");
    }

    /**
     * @custom:scenario Fuzzing the `div256` function
     * @custom:given A 512-bit unsigned integer and a 256-bit unsigned integer
     * @custom:and The divisor is greater than 0
     * @custom:and The divisor is greater than the MSB of the 512-bit integer (to avoid overflowing a uint256)
     * @custom:when The `div256` function is called with the operands
     * @custom:then The result is equal to the division of the 512-bit integer by the 256-bit integer, as a uint256
     * @param a0 The LSB of the numerator
     * @param a1 The MSB of the numerator
     * @param b The divisor
     */
    function testFuzz_FFIDiv256(uint256 a0, uint256 a1, uint256 b) public {
        vm.assume(b > 0);
        vm.assume(a1 < type(uint256).max);
        b = bound(b, a1 + 1, type(uint256).max);
        bytes memory a = abi.encodePacked(a1, a0);
        bytes memory result = vmFFIRustCommand("huge-int-div256", vm.toString(a), vm.toString(b));
        uint256 ref = abi.decode(result, (uint256));
        uint256 res = handler.div(HugeInt.Uint512(a0, a1), b);
        assertEq(res, ref);
    }

    /**
     * @custom:scenario Fuzzing the `div` function
     * @custom:given Two 512-bit unsigned integers
     * @custom:and The divisor is larger than `a / uint256.max` so as to fit the quotient inside a uint256
     * @custom:when The `div` function is called with the operands
     * @custom:then The result is equal to the division of the numerator by the denominator, as a uint256
     */
    function testFuzz_FFIDiv(uint256 a0, uint256 a1, uint256 b0, uint256 b1) public {
        bytes memory a = abi.encodePacked(a1, a0);
        {
            // define bMin
            bytes memory uintMax = abi.encodePacked(uint256(0), type(uint256).max);
            bytes memory temp = vmFFIRustCommand("div512", vm.toString(a), vm.toString(uintMax));
            (uint256 bMin0, uint256 bMin1) = abi.decode(temp, (uint256, uint256));
            // add 1 wei to make sure we account for rounding errors
            if (bMin0 == type(uint256).max && bMin1 < type(uint256).max) {
                bMin1++;
            } else {
                bMin0++;
            }
            // bound b
            b1 = bound(b1, bMin1, type(uint256).max);
            if (b1 == bMin1) {
                b0 = bound(b0, bMin0, type(uint256).max);
            }
        }
        // compute divisions
        bytes memory b = abi.encodePacked(b1, b0);
        bytes memory result = vmFFIRustCommand("huge-int-div", vm.toString(a), vm.toString(b));
        uint256 ref = abi.decode(result, (uint256));
        uint256 res = handler.div(HugeInt.Uint512(a0, a1), HugeInt.Uint512(b0, b1));
        assertEq(res, ref);
    }

    /**
     * @custom:scenario Test the CLZ function
     * @custom:given An unsigned integer
     * @custom:when The CLZ function is applied to the integer
     * @custom:then The number of consecutive zero most-significant bits is returned
     * @param x An unsigned integer
     */
    function testFuzz_FFIClz(uint256 x) public {
        bytes memory result = vmFFIRustCommand("huge-int-clz", vm.toString(x));
        (uint256 ref) = abi.decode(result, (uint256));
        uint256 res = handler.clz(x);
        assertEq(res, ref);
    }

    /**
     * @custom:scenario Test the `_reciprocal` function
     * @custom:given An unsigned integer larger than or equal to 2^255
     * @custom:when The reciprocal is computed
     * @custom:then The result is as expected
     * @param x An unsigned integer
     */
    function testFuzz_FFIReciprocal(uint256 x) public {
        x = bound(x, 2 ** 255, type(uint256).max);
        bytes memory result = vmFFIRustCommand("huge-int-reciprocal", vm.toString(x));
        (uint256 ref) = abi.decode(result, (uint256));
        uint256 res = HugeInt._reciprocal(x);
        assertEq(res, ref);
    }

    /**
     * @custom:scenario Test the `_reciprocal_2` function
     * @custom:given A 512-bit unsigned integer with its high limb larger than or equal to 2^255
     * @custom:when The reciprocal (3/2) is computed
     * @custom:then The result is as expected
     * @param x0 The lower limb of a 512-bit integer
     * @param x1 The higher limb of a 512-bit integer
     */
    function testFuzz_FFIReciprocal2(uint256 x0, uint256 x1) public {
        x1 = bound(x1, 2 ** 255, type(uint256).max);
        bytes memory x = abi.encodePacked(x1, x0);
        bytes memory result = vmFFIRustCommand("huge-int-reciprocal2", vm.toString(x));
        (uint256 ref) = abi.decode(result, (uint256));
        uint256 res = HugeInt._reciprocal_2(x0, x1);
        assertEq(res, ref);
    }
}

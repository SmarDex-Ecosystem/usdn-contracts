// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { HugeUintFixture } from "./utils/Fixtures.sol";

import { HugeUint } from "../../../src/libraries/HugeUint.sol";

/**
 * @custom:feature Fuzzing tests for the `HugeUint` uint512 library
 */
contract TestHugeUintFuzzing is HugeUintFixture {
    function setUp() public override {
        super.setUp();
    }

    /**
     * @custom:scenario Fuzzing the `add` function
     * @custom:given Two 512-bit unsigned integers, the sum of which does not overflow 512 bits
     * @custom:when The `add` function is called with the two integers
     * @custom:then The result is equal to the sum of the two integers
     * @param a0 least-significant bits of the first operand
     * @param a1 most-significant bits of the first operand
     * @param b0 least-significant bits of the second operand
     * @param b1 most-significant bits of the second operand
     */
    function testFuzz_FFIAdd(uint256 a0, uint256 a1, uint256 b0, uint256 b1) public {
        bytes memory a = abi.encodePacked(a1, a0);
        HugeUint.Uint512 memory bMax =
            handler.sub(HugeUint.Uint512(type(uint256).max, type(uint256).max), HugeUint.Uint512(a1, a0));
        b1 = bound(b1, 0, bMax.hi);
        if (b1 == bMax.hi) {
            b0 = bound(b0, 0, bMax.lo);
        }
        bytes memory b = abi.encodePacked(b1, b0);
        bytes memory result = vmFFIRustCommand("huge-uint-add", vm.toString(a), vm.toString(b));
        (uint256 res0, uint256 res1) = abi.decode(result, (uint256, uint256));
        HugeUint.Uint512 memory res = handler.add(HugeUint.Uint512(a1, a0), HugeUint.Uint512(b1, b0));
        assertEq(res.lo, res0, "lo");
        assertEq(res.hi, res1, "hi");
    }

    /**
     * @custom:scenario Reverting when overflow occurs during `add`
     * @custom:given Two 512-bit unsigned integers, the sum of which overflows 512 bits
     * @custom:when The `add` function is called with `a` as the first operand and `b` as the second operand
     * @custom:then The transaction reverts with `HugeUintAddOverflow`
     * @param a0 The LSB of the first operand
     * @param a1 The MSB of the first operand
     * @param b0 The LSB of the second operand
     * @param b1 The MSB of the second operand
     */
    function testFuzz_RevertWhen_addOverflow(uint256 a0, uint256 a1, uint256 b0, uint256 b1) public {
        vm.assume(a0 > 0 || a1 > 0);
        HugeUint.Uint512 memory a = HugeUint.Uint512(a1, a0);
        HugeUint.Uint512 memory bLimit = handler.sub(HugeUint.Uint512(type(uint256).max, type(uint256).max), a);
        bLimit = handler.add(bLimit, HugeUint.Uint512(0, 1));
        b1 = bound(b1, bLimit.hi, type(uint256).max);
        if (b1 == bLimit.hi) {
            b0 = bound(b0, bLimit.lo, type(uint256).max);
        }
        vm.expectRevert(HugeUint.HugeUintAddOverflow.selector);
        handler.add(a, HugeUint.Uint512(b1, b0));
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
        b1 = bound(b1, 0, a1);
        if (b1 == a1) {
            b0 = bound(b0, 0, a0);
        }
        bytes memory b = abi.encodePacked(b1, b0);
        bytes memory result = vmFFIRustCommand("huge-uint-sub", vm.toString(a), vm.toString(b));
        (uint256 res0, uint256 res1) = abi.decode(result, (uint256, uint256));
        HugeUint.Uint512 memory res = handler.sub(HugeUint.Uint512(a1, a0), HugeUint.Uint512(b1, b0));
        assertEq(res.lo, res0, "lo");
        assertEq(res.hi, res1, "hi");
    }

    /**
     * @custom:scenario Reverting when underflow occurs during `sub`
     * @custom:given Two 512-bit unsigned integers, with the second being larger than the first
     * @custom:when The `sub` function is called with `a` as the first operand and `b` as the second operand
     * @custom:then The transaction reverts with `HugeUintSubUnderflow`
     * @param a0 The LSB of the first operand
     * @param a1 The MSB of the first operand
     * @param b0 The LSB of the second operand
     * @param b1 The MSB of the second operand
     */
    function testFuzz_RevertWhen_subUnderflow(uint256 a0, uint256 a1, uint256 b0, uint256 b1) public {
        vm.assume(a0 < type(uint256).max || a1 < type(uint256).max);
        HugeUint.Uint512 memory a = HugeUint.Uint512(a1, a0);
        HugeUint.Uint512 memory bLimit = handler.add(a, HugeUint.Uint512(0, 1));
        b1 = bound(b1, bLimit.hi, type(uint256).max);
        if (b1 == bLimit.hi) {
            b0 = bound(b0, bLimit.lo, type(uint256).max);
        }
        vm.expectRevert(HugeUint.HugeUintSubUnderflow.selector);
        handler.sub(a, HugeUint.Uint512(b1, b0));
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
        bytes memory result = vmFFIRustCommand("huge-uint-mul256", vm.toString(a), vm.toString(b));
        (uint256 res0, uint256 res1) = abi.decode(result, (uint256, uint256));
        HugeUint.Uint512 memory res = handler.mul(a, b);
        assertEq(res.lo, res0, "lo");
        assertEq(res.hi, res1, "hi");
    }

    /**
     * @custom:scenario Fuzzing the `mul` function
     * @custom:given A 512-bit unsigned integer and a 256-bit unsigned integer
     * @custom:when The `mul` function is called with the two integers
     * @custom:then The result is equal to the product of the two integers as a `Uint512`
     * @param a0 least-significant bits of the first operand
     * @param a1 most-significant bits of the first operand
     * @param b the second operand
     */
    function testFuzz_FFIMul512(uint256 a0, uint256 a1, uint256 b) public {
        bytes memory a = abi.encodePacked(a1, a0);
        if (a0 > 0 || a1 > 0) {
            // determine the maximum value of b
            bytes memory uintMax = abi.encodePacked(type(uint256).max, type(uint256).max);
            bytes memory temp = vmFFIRustCommand("div512", vm.toString(uintMax), vm.toString(a));
            (uint256 bMax0, uint256 bMax1) = abi.decode(temp, (uint256, uint256));
            // bound b
            if (bMax1 == 0) {
                b = bound(b, 0, bMax0);
            }
        }
        bytes memory bBytes = abi.encodePacked(uint256(0), b);
        bytes memory result = vmFFIRustCommand("huge-uint-mul", vm.toString(a), vm.toString(bBytes));
        (uint256 res0, uint256 res1) = abi.decode(result, (uint256, uint256));
        HugeUint.Uint512 memory res = handler.mul(HugeUint.Uint512(a1, a0), b);
        assertEq(res.lo, res0, "lo");
        assertEq(res.hi, res1, "hi");
    }

    /**
     * @custom:scenario Reverting when overflow occurs during `mul`
     * @custom:given A 512-bit unsigned integer and a 256-bit unsigned integer, the product of which exceeds uint512.max
     * @custom:when The `mul` function is called with the two integers
     * @custom:then The transaction reverts with `HugeUintMulOverflow`
     * @param a0 The LSB of the first operand
     * @param a1 The MSB of the first operand
     * @param b The second operand
     */
    function testFuzz_RevertWhen_FFIMul512Overflow(uint256 a0, uint256 a1, uint256 b) public {
        vm.assume(a0 > 0 || a1 > 0);
        bytes memory uintMax = abi.encodePacked(type(uint256).max, type(uint256).max);
        bytes memory temp = vmFFIRustCommand("div512", vm.toString(uintMax), vm.toString(abi.encodePacked(a1, a0)));
        (uint256 bLimit0, uint256 bLimit1) = abi.decode(temp, (uint256, uint256));
        if (bLimit1 == type(uint256).max && bLimit0 == type(uint256).max) {
            // we can't overflow the multiplication in this case
            return;
        }
        HugeUint.Uint512 memory bLimit = handler.add(HugeUint.Uint512(bLimit1, bLimit0), HugeUint.Uint512(0, 1));
        if (bLimit.hi > 0) {
            // we can't overflow the multiplication in this case
            return;
        }
        b = bound(b, bLimit.lo, type(uint256).max);
        vm.expectRevert(HugeUint.HugeUintMulOverflow.selector);
        handler.mul(HugeUint.Uint512(a1, a0), b);
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
        bytes memory result = vmFFIRustCommand("huge-uint-div256", vm.toString(a), vm.toString(b));
        uint256 ref = abi.decode(result, (uint256));
        uint256 res = handler.div(HugeUint.Uint512(a1, a0), b);
        assertEq(res, ref);
    }

    /**
     * @custom:scenario Reverting when division by zero occurs during `div`
     * @custom:given A 512-bit unsigned integer
     * @custom:when The `div` function is called with the integer and 0
     * @custom:then The transaction reverts with `HugeUintDivisionFailed`
     * @param a0 The LSB of the 512-bit integer
     * @param a1 The MSB of the 512-bit integer
     */
    function testFuzz_RevertWhen_div256ByZero(uint256 a0, uint256 a1) public {
        // division by zero always fails
        vm.expectRevert(HugeUint.HugeUintDivisionFailed.selector);
        handler.div(HugeUint.Uint512(a1, a0), 0);
    }

    /**
     * @custom:scenario Reverting when the division overflows 256 bits
     * @custom:given A 512-bit unsigned integer larger than uint256.max
     * @custom:and a divisor which is larger than 0 but smaller than the MSB of the 512-bit integer
     * @custom:when The `div` function is called with the operands
     * @custom:then The transaction reverts with `HugeUintDivisionFailed`
     * @param a0 The LSB of the 512-bit numerator
     * @param a1 The MSB of the 512-bit numerator
     * @param b The divisor
     */
    function testFuzz_RevertWhen_div256Overflow(uint256 a0, uint256 a1, uint256 b) public {
        vm.assume(b > 0 && a1 > 0); // we can't overflow if a1 is zero
        b = bound(b, 1, a1);
        vm.expectRevert(HugeUint.HugeUintDivisionFailed.selector);
        handler.div(HugeUint.Uint512(a1, a0), b);
    }

    /**
     * @custom:scenario Fuzzing the `div(Uint512,uint512)` function
     * @custom:given Two 512-bit unsigned integers
     * @custom:and The divisor is larger than `a / uint256.max` so as to fit the quotient inside a uint256
     * @custom:when The `div` function is called with the operands
     * @custom:then The result is equal to the division of the numerator by the denominator, as a uint256
     * @param a0 The LSB of the numerator
     * @param a1 The MSB of the numerator
     * @param b0 The LSB of the denominator
     * @param b1 The MSB of the denominator
     */
    function testFuzz_FFIDiv512(uint256 a0, uint256 a1, uint256 b0, uint256 b1) public {
        bytes memory a = abi.encodePacked(a1, a0);
        {
            // define bMin
            bytes memory uintMax = abi.encodePacked(uint256(0), type(uint256).max);
            bytes memory temp = vmFFIRustCommand("div-up512", vm.toString(a), vm.toString(uintMax));
            (uint256 bMin0, uint256 bMin1) = abi.decode(temp, (uint256, uint256));
            // bound b
            b1 = bound(b1, bMin1, type(uint256).max);
            if (b1 == bMin1) {
                b0 = bound(b0, bMin0, type(uint256).max);
            }
            if (b1 == 0 && b0 == 0) {
                b0 = 1;
            }
        }
        // compute divisions
        bytes memory b = abi.encodePacked(b1, b0);
        bytes memory result = vmFFIRustCommand("huge-uint-div", vm.toString(a), vm.toString(b));
        uint256 ref = abi.decode(result, (uint256));
        uint256 res = handler.div(HugeUint.Uint512(a1, a0), HugeUint.Uint512(b1, b0));
        assertEq(res, ref);
    }

    /**
     * @custom:scenario Reverting when division by zero occurs during `div(Uint512,Uint512)`
     * @custom:given A 512-bit unsigned integer
     * @custom:when The `div` function is called with the integer and 0
     * @custom:then The transaction reverts with `HugeUintDivisionFailed`
     * @param a0 The LSB of the 512-bit integer
     * @param a1 The MSB of the 512-bit integer
     */
    function testFuzz_RevertWhen_div512ByZero(uint256 a0, uint256 a1) public {
        // division by zero always fails
        vm.expectRevert(HugeUint.HugeUintDivisionFailed.selector);
        handler.div(HugeUint.Uint512(a1, a0), HugeUint.Uint512(0, 0));
    }

    /**
     * @custom:scenario Reverting when the division overflows 256 bits
     * @custom:given Two 512-bit unsigned integers, the division of which overflows 256 bits
     * @custom:when The `div` function is called with the operands
     * @custom:then The transaction reverts with `HugeUintDivisionFailed`
     * @param a0 The LSB of the 512-bit numerator
     * @param a1 The MSB of the 512-bit numerator
     * @param b0 The LSB of the 512-bit denominator
     * @param b1 The MSB of the 512-bit denominator
     */
    function testFuzz_RevertWhen_FFIDiv512Overflow(uint256 a0, uint256 a1, uint256 b0, uint256 b1) public {
        bytes memory a = abi.encodePacked(a1, a0);
        // define bLimit
        bytes memory temp =
            vmFFIRustCommand("div512", vm.toString(a), vm.toString(abi.encodePacked(uint256(0), type(uint256).max)));
        (uint256 bLimit0, uint256 bLimit1) = abi.decode(temp, (uint256, uint256));
        if (bLimit0 == 0 && bLimit1 == 0) {
            // we can't overflow in this case
            return;
        }
        HugeUint.Uint512 memory bLimit = HugeUint.Uint512(bLimit1, bLimit0);
        if (bLimit0 == 1 && bLimit1 == 1) {
            // Special case: `a = uint512.max`. The division of `a` by `uint256.max` gives `bLimit = uint256.max+2`.
            // If we were to subtract 1 to enter the range that should overflow, we get `b = uint256.max+1`. However,
            // the division `uint512.max / (uint256.max+1)` does not overflow due to the rounding.
            // To ensure the overflow, we subtract 2 instead.
            // We test this case in unit tests.
            bLimit = handler.sub(bLimit, HugeUint.Uint512(0, 2));
        } else {
            bLimit = handler.sub(bLimit, HugeUint.Uint512(0, 1));
        }
        // bound b
        b1 = bound(b1, 0, bLimit.hi);
        if (b1 == bLimit.hi) {
            b0 = bound(b0, 0, bLimit.lo);
        }
        if (b1 == 0 && b0 == 0) {
            return;
        }

        vm.expectRevert(HugeUint.HugeUintDivisionFailed.selector);
        handler.div(HugeUint.Uint512(a1, a0), HugeUint.Uint512(b1, b0));
    }

    /**
     * @custom:scenario Fuzzing the reciprocity of the `mul` and `div` functions
     * @custom:given Two 256-bit unsigned integers
     * @custom:when The `mul` function is called with the two integers
     * @custom:and The `div` function is called with the product and one of the integers
     * @custom:then The result of the `div` function is equal to the other integer
     * @param a the first operand
     * @param b the second operand
     */
    function testFuzz_mulThenDiv(uint256 a, uint256 b) public view {
        vm.assume(a > 0 && b > 0);
        HugeUint.Uint512 memory m = handler.mul(a, b);
        uint256 res = handler.div(m, b);
        assertEq(res, a, "res");
        uint256 res2 = handler.div(m, a);
        assertEq(res2, b, "res2");
    }

    /**
     * @custom:scenario Fuzzing the reciprocity of the `div` and `mul` functions
     * @custom:given Two 512-bit unsigned integers which division does not overflow 256 bits
     * @custom:when The `div` function is called with the numerator and the divisor
     * @custom:and The `mul` function is called with the quotient and the divisor
     * @custom:then The result of the `mul` function is lower than or equal to the difference between the numerator and
     * the divisor (due to rounding errors, the result may not be exactly equal to the numerator)
     * @custom:and The result of the `mul` function is lower than or equal to the numerator
     * @param a0 The LSB of the numerator
     * @param a1 The MSB of the numerator
     * @param b0 The LSB of the divisor
     * @param b1 The MSB of the divisor
     */
    function testFuzz_FFIDivThenMul(uint256 a0, uint256 a1, uint256 b0, uint256 b1) public {
        {
            // define bMin
            bytes memory uintMax = abi.encodePacked(uint256(0), type(uint256).max);
            bytes memory temp =
                vmFFIRustCommand("div-up512", vm.toString(abi.encodePacked(a1, a0)), vm.toString(uintMax));
            (uint256 bMin0, uint256 bMin1) = abi.decode(temp, (uint256, uint256));
            // bound b
            b1 = bound(b1, bMin1, type(uint256).max);
            if (b1 == bMin1) {
                b0 = bound(b0, bMin0, type(uint256).max);
            }
            if (b1 == 0 && b0 == 0) {
                b0 = 1;
            }
        }
        HugeUint.Uint512 memory a = HugeUint.Uint512(a1, a0);
        HugeUint.Uint512 memory b = HugeUint.Uint512(b1, b0);
        uint256 d = handler.div(a, b);
        // if b > a, then the result is 0 and we don't need to test further
        if (d == 0) {
            return;
        }
        HugeUint.Uint512 memory res = handler.mul(b, d);
        HugeUint.Uint512 memory aMinusB = handler.sub(a, b);
        assertTrue(res.hi > aMinusB.hi || (res.hi == aMinusB.hi && res.lo > aMinusB.lo), "res > a - b");
        assertTrue(res.hi < a.hi || (res.hi == a.hi && res.lo <= a.lo), "res <= a");
    }

    /**
     * @custom:scenario Test the CLZ function
     * @custom:given An unsigned integer
     * @custom:when The CLZ function is applied to the integer
     * @custom:then The number of consecutive zero most-significant bits is returned
     * @param x An unsigned integer
     */
    function testFuzz_FFIClz(uint256 x) public {
        bytes memory result = vmFFIRustCommand("huge-uint-clz", vm.toString(x));
        (uint256 ref) = abi.decode(result, (uint256));
        uint256 res = HugeUint._clz(x);
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
        bytes memory result = vmFFIRustCommand("huge-uint-reciprocal", vm.toString(x));
        (uint256 ref) = abi.decode(result, (uint256));
        uint256 res = HugeUint._reciprocal(x);
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
        bytes memory result = vmFFIRustCommand("huge-uint-reciprocal2", vm.toString(x));
        (uint256 ref) = abi.decode(result, (uint256));
        uint256 res = HugeUint._reciprocal_2(x0, x1);
        assertEq(res, ref);
    }
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { FixedPointMathLib } from "solady/src/utils/FixedPointMathLib.sol";

import { SignedMathFixture } from "./utils/Fixtures.sol";

import { SignedMath } from "../../../src/libraries/SignedMath.sol";

/**
 * @custom:feature Fuzzing tests for conversion functions in `SignedMath`
 */
contract TestSignedMathFuzzing is SignedMathFixture {
    using FixedPointMathLib for int256;

    function setUp() public override {
        super.setUp();
    }

    /**
     * @custom:scenario Adding two operands
     * @custom:given Two operands as signed integers
     * @custom:when The operands are added together with the `safeAdd` function
     * @custom:and The result does not overflow a signed integer
     * @custom:or The result overflows a signed integer
     * @custom:then The result is equal to the sum of the operands
     * @custom:or The result reverts with a custom error
     * @param lhs left-hand side operand
     * @param rhs right-hand side operand
     */
    function testFuzz_safeAdd(int256 lhs, int256 rhs) public {
        if (
            (lhs > 0 && rhs > 0 && rhs > type(int256).max - lhs) || (lhs < 0 && rhs < 0 && rhs < type(int256).min - lhs)
        ) {
            vm.expectRevert(abi.encodeWithSelector(SignedMath.SignedMathOverflowedAdd.selector, lhs, rhs));
            handler.safeAdd(lhs, rhs);
            return;
        }
        assertEq(handler.safeAdd(lhs, rhs), lhs + rhs);
    }

    /**
     * @custom:scenario Subtracting two operands
     * @custom:given Two operands as signed integers
     * @custom:when The operands are subtracted with the `safeSub` function
     * @custom:and The result does not overflow a signed integer
     * @custom:or The result overflows a signed integer
     * @custom:then The result is equal to the subtraction of the operands
     * @custom:or The result reverts with a custom error
     * @param lhs left-hand side operand
     * @param rhs right-hand side operand
     */
    function testFuzz_safeSub(int256 lhs, int256 rhs) public {
        if ((rhs > 0 && lhs < type(int256).min + rhs) || (rhs < 0 && lhs > type(int256).max + rhs)) {
            vm.expectRevert(abi.encodeWithSelector(SignedMath.SignedMathOverflowedSub.selector, lhs, rhs));
            handler.safeSub(lhs, rhs);
            return;
        }
        assertEq(handler.safeSub(lhs, rhs), lhs - rhs);
    }

    /**
     * @custom:scenario Multiplying two operands
     * @custom:given Two operands as signed integers
     * @custom:when The operands are multiplied together with the `safeMul` function
     * @custom:and The result does not overflow a signed integer
     * @custom:or The result overflows a signed integer
     * @custom:then The result is equal to the product of the operands
     * @custom:or The result reverts with a custom error
     * @param lhs left-hand side operand
     * @param rhs right-hand side operand
     */
    function testFuzz_safeMul(int256 lhs, int256 rhs) public {
        if (
            (lhs > 0 && rhs > 0 && rhs > type(int256).max / lhs)
                || (lhs < 0 && rhs < 0 && rhs.abs() > uint256(type(int256).max) / lhs.abs())
                || (lhs > 0 && rhs < 0 && rhs < type(int256).min / lhs)
                || (lhs < 0 && rhs > 0 && lhs < type(int256).min / rhs)
        ) {
            vm.expectRevert(abi.encodeWithSelector(SignedMath.SignedMathOverflowedMul.selector, lhs, rhs));
            handler.safeMul(lhs, rhs);
            return;
        }
        assertEq(handler.safeMul(lhs, rhs), lhs * rhs);
    }

    /**
     * @custom:scenario Dividing two operands
     * @custom:given Two operands as signed integers
     * @custom:when The operands are divided with the `safeDiv` function
     * @custom:and The `rhs` operand is not equal to zero
     * @custom:or The `rhs` operand is equal to zero
     * @custom:then The result is equal to the quotient of the operands
     * @custom:or The result reverts with a custom error
     * @param lhs left-hand side operand
     * @param rhs right-hand side operand
     */
    function testFuzz_safeDiv(int256 lhs, int256 rhs) public {
        if (rhs == 0) {
            vm.expectRevert(abi.encodeWithSelector(SignedMath.SignedMathDivideByZero.selector, lhs));
            handler.safeDiv(lhs, rhs);
            return;
        } else if (lhs == type(int256).min && rhs == -1) {
            vm.expectRevert(abi.encodeWithSelector(SignedMath.SignedMathOverflowedDiv.selector, lhs, rhs));
            handler.safeDiv(lhs, rhs);
            return;
        }
        assertEq(handler.safeDiv(lhs, rhs), lhs / rhs);
    }
}

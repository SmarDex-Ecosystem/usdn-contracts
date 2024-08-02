// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { SignedMathFixture } from "./utils/Fixtures.sol";

import { SignedMath } from "../../../src/libraries/SignedMath.sol";

/**
 * @custom:feature Test functions in `SignedMath`
 * @custom:background Given operands are signed 256 bit integers
 */
contract TestSignedMathConcrete is SignedMathFixture {
    function setUp() public override {
        super.setUp();
    }

    /**
     * @custom:scenario Add two operands
     * @custom:given The operands lead to no overflow
     * @custom:when Calling `safeAdd`
     * @custom:then Return the sum of the operands
     */
    function test_safeAdd() public view {
        assertEq(handler.safeAdd(42, 69), 111, "positive + positive");
        assertEq(handler.safeAdd(-42, 69), 27, "negative + positive");
        assertEq(handler.safeAdd(42, -69), -27, "positive + negative");
        assertEq(handler.safeAdd(-42, -69), -111, "negative + negative");
    }

    /**
     * @custom:scenario Add two operands
     * @custom:given The operands lead to overflow
     * @custom:when Calling `safeAdd`
     * @custom:then Revert with `SignedMathOverflowedAdd`
     */
    function test_RevertWhen_addOverflow() public {
        int256 lhs = type(int256).max;
        int256 rhs = 1;
        vm.expectRevert(abi.encodeWithSelector(SignedMath.SignedMathOverflowedAdd.selector, lhs, rhs));
        handler.safeAdd(lhs, rhs);

        rhs = type(int256).max;
        vm.expectRevert(abi.encodeWithSelector(SignedMath.SignedMathOverflowedAdd.selector, lhs, rhs));
        handler.safeAdd(lhs, rhs);
    }

    /**
     * @custom:scenario Add two operands
     * @custom:given The operands lead to underflow
     * @custom:when Calling `safeAdd`
     * @custom:then Revert with `SignedMathOverflowedAdd`
     */
    function test_RevertWhen_addUnderflow() public {
        int256 lhs = type(int256).min;
        int256 rhs = -1;
        vm.expectRevert(abi.encodeWithSelector(SignedMath.SignedMathOverflowedAdd.selector, lhs, rhs));
        handler.safeAdd(lhs, rhs);

        rhs = type(int256).min;
        vm.expectRevert(abi.encodeWithSelector(SignedMath.SignedMathOverflowedAdd.selector, lhs, rhs));
        handler.safeAdd(lhs, rhs);
    }

    /**
     * @custom:scenario Subtract two operands
     * @custom:given The operands lead to no overflow
     * @custom:when Calling `safeSub`
     * @custom:then Return the difference of the operands
     */
    function test_safeSub() public view {
        assertEq(handler.safeSub(42, 69), -27, "positive - positive");
        assertEq(handler.safeSub(-42, 69), -111, "negative - positive");
        assertEq(handler.safeSub(42, -69), 111, "positive - negative");
        assertEq(handler.safeSub(-42, -69), 27, "negative - negative");
    }

    /**
     * @custom:scenario Subtract two operands
     * @custom:given The operands lead to overflow
     * @custom:when Calling `safeSub`
     * @custom:then Revert with `SignedMathOverflowedSub`
     */
    function test_RevertWhen_subOverflow() public {
        int256 lhs = type(int256).max;
        int256 rhs = -1;
        vm.expectRevert(abi.encodeWithSelector(SignedMath.SignedMathOverflowedSub.selector, lhs, rhs));
        handler.safeSub(lhs, rhs);

        rhs = type(int256).min;
        vm.expectRevert(abi.encodeWithSelector(SignedMath.SignedMathOverflowedSub.selector, lhs, rhs));
        handler.safeSub(lhs, rhs);
    }

    /**
     * @custom:scenario Subtract two operands
     * @custom:given The operands lead to underflow
     * @custom:when Calling `safeSub`
     * @custom:then Revert with `SignedMathOverflowedSub`
     */
    function test_RevertWhen_subUnderflow() public {
        int256 lhs = type(int256).min;
        int256 rhs = 1;
        vm.expectRevert(abi.encodeWithSelector(SignedMath.SignedMathOverflowedSub.selector, lhs, rhs));
        handler.safeSub(lhs, rhs);

        rhs = type(int256).max;
        vm.expectRevert(abi.encodeWithSelector(SignedMath.SignedMathOverflowedSub.selector, lhs, rhs));
        handler.safeSub(lhs, rhs);
    }

    /**
     * @custom:scenario Multiply two operands
     * @custom:given The operands lead to no overflow
     * @custom:when Calling `safeMul`
     * @custom:then Return the product of the operands
     */
    function test_safeMul() public view {
        assertEq(handler.safeMul(42, 69), 2898, "positive * positive");
        assertEq(handler.safeMul(-42, 69), -2898, "negative * positive");
        assertEq(handler.safeMul(-42, -69), 2898, "negative * negative");
        assertEq(handler.safeMul(42, -69), -2898, "positive * negative");
        assertEq(handler.safeMul(0, 69), 0, "zero * positive");
    }

    /**
     * @custom:scenario Multiply two operands
     * @custom:given The operands lead to overflow
     * @custom:when Calling `safeMul`
     * @custom:then Revert with `SignedMathOverflowedMul`
     */
    function test_RevertWhen_mulOverflow() public {
        int256 lhs = type(int256).max;
        int256 rhs = 2;
        vm.expectRevert(abi.encodeWithSelector(SignedMath.SignedMathOverflowedMul.selector, lhs, rhs));
        handler.safeMul(lhs, rhs);

        // invert lhs and rhs
        vm.expectRevert(abi.encodeWithSelector(SignedMath.SignedMathOverflowedMul.selector, rhs, lhs));
        handler.safeMul(rhs, lhs);

        rhs = type(int256).max;
        vm.expectRevert(abi.encodeWithSelector(SignedMath.SignedMathOverflowedMul.selector, lhs, rhs));
        handler.safeMul(lhs, rhs);

        lhs = -1;
        rhs = type(int256).min;
        vm.expectRevert(abi.encodeWithSelector(SignedMath.SignedMathOverflowedMul.selector, lhs, rhs));
        handler.safeMul(lhs, rhs);
    }

    /**
     * @custom:scenario Multiply two operands
     * @custom:given The operands lead to underflow
     * @custom:when Calling `safeMul`
     * @custom:then Revert with `SignedMathOverflowedMul`
     */
    function test_RevertWhen_mulUnderflow() public {
        int256 lhs = type(int256).min;
        int256 rhs = 2;
        vm.expectRevert(abi.encodeWithSelector(SignedMath.SignedMathOverflowedMul.selector, lhs, rhs));
        handler.safeMul(lhs, rhs);

        // invert lhs and rhs
        vm.expectRevert(abi.encodeWithSelector(SignedMath.SignedMathOverflowedMul.selector, rhs, lhs));
        handler.safeMul(rhs, lhs);

        rhs = type(int256).min;
        vm.expectRevert(abi.encodeWithSelector(SignedMath.SignedMathOverflowedMul.selector, lhs, rhs));
        handler.safeMul(lhs, rhs);
    }

    /**
     * @custom:scenario Divide two operands
     * @custom:given The second operand is non-zero
     * @custom:when Calling `safeDiv`
     * @custom:then Return the quotient of the operands
     */
    function test_safeDiv() public view {
        assertEq(handler.safeDiv(420, 69), 6, "positive / positive");
        assertEq(handler.safeDiv(-420, 69), -6, "negative / positive");
        assertEq(handler.safeDiv(420, -69), -6, "positive / negative");
        assertEq(handler.safeDiv(-420, -69), 6, "negative / negative");
    }

    /**
     * @custom:scenario Divide two operands
     * @custom:given The second operand is zero
     * @custom:when Calling `safeDiv`
     * @custom:then Revert with `SignedMathDivideByZero`
     */
    function test_RevertWhen_divZero() public {
        int256 lhs = 42;
        vm.expectRevert(abi.encodeWithSelector(SignedMath.SignedMathDivideByZero.selector, lhs));
        handler.safeDiv(lhs, 0);

        lhs = -42;
        vm.expectRevert(abi.encodeWithSelector(SignedMath.SignedMathDivideByZero.selector, lhs));
        handler.safeDiv(lhs, 0);
    }

    /**
     * @custom:scenario Divide two operands
     * @custom:given The first operand is int256.min and the second operand is -1
     * @custom:when Calling `safeDiv`
     * @custom:then Revert with `SignedMathOverflowedDiv`
     */
    function test_RevertWhen_divOverflow() public {
        int256 lhs = type(int256).min;
        int256 rhs = -1;
        vm.expectRevert(abi.encodeWithSelector(SignedMath.SignedMathOverflowedDiv.selector, lhs, rhs));
        handler.safeDiv(lhs, rhs);
    }
}

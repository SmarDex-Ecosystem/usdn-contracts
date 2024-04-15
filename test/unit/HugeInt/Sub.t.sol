// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { HugeIntFixture } from "test/unit/HugeInt/utils/Fixtures.sol";

import { HugeInt } from "src/libraries/HugeInt.sol";

/**
 * @custom:feature Unit tests for the `sub` function of the `HugeInt` uint512 library
 */
contract TestHugeIntSub is HugeIntFixture {
    function setUp() public override {
        super.setUp();
    }

    /**
     * @custom:scenario Testing the `sub` function
     * @custom:given Two 512-bit unsigned integers
     * @custom:when The `sub` function is called with the 69 and 42
     * @custom:then The result is equal to 27
     * @custom:when The `sub` function is called with 1 and 0
     * @custom:then The result is equal to 1
     * @custom:when The `sub` function is called with `uint512.max` and `uint512.max`
     * @custom:then The result is equal to 0
     * @custom:when The `sub` function is called with `uint512.max` and 1
     * @custom:then The result is equal to `uint512.max - 1`
     */
    function test_sub() public {
        HugeInt.Uint512 memory a = HugeInt.Uint512(69, 0);
        HugeInt.Uint512 memory b = HugeInt.Uint512(42, 0);
        HugeInt.Uint512 memory res = HugeInt.sub(a, b);
        assertEq(res.lo, 27, "27: lo");
        assertEq(res.hi, 0, "27: hi");

        a = HugeInt.Uint512(1, 0);
        b = HugeInt.Uint512(0, 0);
        res = HugeInt.sub(a, b);
        assertEq(res.lo, 1, "one: lo");
        assertEq(res.hi, 0, "one: hi");

        a = HugeInt.Uint512(type(uint256).max, type(uint256).max);
        b = a;
        res = HugeInt.sub(a, b);
        assertEq(res.lo, 0, "zero: lo");
        assertEq(res.hi, 0, "zero: hi");

        a = HugeInt.Uint512(type(uint256).max, type(uint256).max);
        b = HugeInt.Uint512(1, 0);
        res = HugeInt.sub(a, b);
        assertEq(res.lo, type(uint256).max - 1, "max-1: lo");
        assertEq(res.hi, type(uint256).max, "max-1: hi");
    }

    /**
     * @custom:scenario Reverting when underflow occurs
     * @custom:given Two 512-bit unsigned integers, the difference of which underflows
     * @custom:when The `sub` function is called with 0 and 1
     * @custom:then The transaction reverts
     * @custom:when The `sub` function is called with `uint512.max - 1` and `uint512.max`
     * @custom:then The transaction reverts
     */
    function test_RevertWhen_subUnderflow() public {
        HugeInt.Uint512 memory a = HugeInt.Uint512(0, 0);
        HugeInt.Uint512 memory b = HugeInt.Uint512(1, 0);
        vm.expectRevert(HugeInt.HugeIntSubUnderflow.selector);
        handler.sub(a, b);

        a = HugeInt.Uint512(type(uint256).max - 1, type(uint256).max);
        b = HugeInt.Uint512(type(uint256).max, type(uint256).max);
        vm.expectRevert(HugeInt.HugeIntSubUnderflow.selector);
        handler.sub(a, b);
    }
}

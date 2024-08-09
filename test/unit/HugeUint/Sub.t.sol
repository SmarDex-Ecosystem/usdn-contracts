// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { HugeUintFixture } from "./utils/Fixtures.sol";

import { HugeUint } from "../../../src/libraries/HugeUint.sol";

/**
 * @custom:feature Unit tests for the `sub` function of the `HugeUint` uint512 library
 */
contract TestHugeUintSub is HugeUintFixture {
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
    function test_sub() public pure {
        HugeUint.Uint512 memory a = HugeUint.Uint512(0, 69);
        HugeUint.Uint512 memory b = HugeUint.Uint512(0, 42);
        HugeUint.Uint512 memory res = HugeUint.sub(a, b);
        assertEq(res.lo, 27, "69-42: lo");
        assertEq(res.hi, 0, "69-42: hi");

        a = HugeUint.Uint512(0, 1);
        b = HugeUint.Uint512(0, 0);
        res = HugeUint.sub(a, b);
        assertEq(res.lo, 1, "1-0: lo");
        assertEq(res.hi, 0, "1-0: hi");

        a = HugeUint.Uint512(type(uint256).max, type(uint256).max);
        b = a;
        res = HugeUint.sub(a, b);
        assertEq(res.lo, 0, "max-max: lo");
        assertEq(res.hi, 0, "max-max: hi");

        a = HugeUint.Uint512(type(uint256).max, type(uint256).max);
        b = HugeUint.Uint512(0, 1);
        res = HugeUint.sub(a, b);
        assertEq(res.lo, type(uint256).max - 1, "max-1: lo");
        assertEq(res.hi, type(uint256).max, "max-1: hi");
    }

    /**
     * @custom:scenario Reverting when underflow occurs
     * @custom:given Two 512-bit unsigned integers, the difference of which underflows
     * @custom:when The `sub` function is called with 0 and 1
     * @custom:or The `sub` function is called with `uint512.max - 1` and `uint512.max`
     * @custom:then The transaction reverts
     */
    function test_RevertWhen_subUnderflow() public {
        HugeUint.Uint512 memory a = HugeUint.Uint512(0, 0);
        HugeUint.Uint512 memory b = HugeUint.Uint512(0, 1);
        vm.expectRevert(HugeUint.HugeUintSubUnderflow.selector);
        handler.sub(a, b);

        a = HugeUint.Uint512(type(uint256).max, type(uint256).max - 1);
        b = HugeUint.Uint512(type(uint256).max, type(uint256).max);
        vm.expectRevert(HugeUint.HugeUintSubUnderflow.selector);
        handler.sub(a, b);
    }
}

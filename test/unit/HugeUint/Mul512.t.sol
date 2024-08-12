// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { HugeUintFixture } from "./utils/Fixtures.sol";

import { HugeUint } from "../../../src/libraries/HugeUint.sol";

/**
 * @custom:feature Unit tests for the `mul(Uint512,uint256)` function of the `HugeUint` uint512 library
 */
contract TestHugeUintMul512 is HugeUintFixture {
    function setUp() public override {
        super.setUp();
    }

    /**
     * @custom:scenario Testing the `mul` function
     * @custom:given A 512-bit unsigned integer and a 256-bit unsigned integer
     * @custom:when The `mul` function is called with 69 and 42
     * @custom:then The result is equal to 2898
     * @custom:when The `mul` function is called with `uint512.max` and 0
     * @custom:then The result is equal to 0
     * @custom:when The `mul` function is called with 0 and `uint256.max`
     * @custom:then The result is equal to 0
     * @custom:when The `mul` function is called with `uint256.max` and 1
     * @custom:then The result is equal to `uint256.max`
     * @custom:when The `mul` function is called with 1 and `uint256.max`
     * @custom:then The result is equal to `uint256.max`
     * @custom:when The `mul` function is called with `uint256.max+2` and `uint256.max`
     * @custom:then The result is equal to `uint512.max`
     */
    function test_mul() public view {
        HugeUint.Uint512 memory a = HugeUint.Uint512(0, 69);
        uint256 b = 42;
        HugeUint.Uint512 memory res = handler.mul(a, b);
        assertEq(res.lo, 2898, "69*42: lo");
        assertEq(res.hi, 0, "69*42: hi");

        a = HugeUint.Uint512(type(uint256).max, type(uint256).max);
        b = 0;
        res = handler.mul(a, b);
        assertEq(res.lo, 0, "1*0: lo");
        assertEq(res.hi, 0, "1*0: hi");

        a = HugeUint.Uint512(0, 0);
        b = type(uint256).max;
        res = handler.mul(a, b);
        assertEq(res.lo, 0, "0*uint256.max: lo");
        assertEq(res.hi, 0, "0*uint256.max: hi");

        a = HugeUint.Uint512(0, type(uint256).max);
        b = 1;
        res = handler.mul(a, b);
        assertEq(res.lo, type(uint256).max, "uint256.max*1: lo");
        assertEq(res.hi, 0, "uint256.max*1: hi");

        a = HugeUint.Uint512(type(uint256).max, type(uint256).max);
        b = 1;
        res = handler.mul(a, b);
        assertEq(res.lo, type(uint256).max, "uint512.max*1: lo");
        assertEq(res.hi, type(uint256).max, "uint512.max*1: hi");

        a = HugeUint.Uint512(0, 1);
        b = type(uint256).max;
        res = handler.mul(a, b);
        assertEq(res.lo, type(uint256).max, "1*uint256.max: lo");
        assertEq(res.hi, 0, "1*uint256.max: hi");

        a = HugeUint.Uint512(1, 1);
        b = type(uint256).max;
        res = handler.mul(a, b);
        assertEq(res.lo, type(uint256).max, "uint256.max+2 * uint256.max: lo");
        assertEq(res.hi, type(uint256).max, "uint256.max+2 * uint256.max: hi");
    }

    /**
     * @custom:scenario Reverting when overflow occurs
     * @custom:given Two 512-bit unsigned integers, the product of which overflows 512 bits
     * @custom:when The `mul` function is called with `uint512.max` and 2
     * @custom:or The `mul` function is called with `uint256.max+3` and `uint256.max`
     * @custom:then The transaction reverts
     */
    function test_RevertWhen_mulOverflow() public {
        HugeUint.Uint512 memory a = HugeUint.Uint512(type(uint256).max, type(uint256).max);
        uint256 b = 2;
        vm.expectRevert(HugeUint.HugeUintMulOverflow.selector);
        handler.mul(a, b);

        a = HugeUint.Uint512(1, 2);
        b = type(uint256).max;
        vm.expectRevert(HugeUint.HugeUintMulOverflow.selector);
        handler.mul(a, b);
    }
}

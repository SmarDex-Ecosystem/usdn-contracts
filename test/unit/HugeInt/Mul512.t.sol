// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { HugeIntFixture } from "test/unit/HugeInt/utils/Fixtures.sol";

import { HugeInt } from "src/libraries/HugeInt.sol";

/**
 * @custom:feature Unit tests for the `mul(Uint512,Uint512)` function of the `HugeInt` uint512 library
 */
contract TestHugeIntMul512 is HugeIntFixture {
    function setUp() public override {
        super.setUp();
    }

    /**
     * @custom:scenario Testing the `mul` function
     * @custom:given Two 512-bit unsigned integers which product does not overflow 512 bits
     * @custom:when The `mul` function is called with 69 and 42
     * @custom:then The result is equal to 2898
     * @custom:when The `mul` function is called with 1 and 0
     * @custom:then The result is equal to 0
     * @custom:when The `mul` function is called with `uint256.max` and `uint256.max + 2`
     * @custom:then The result is equal to `uint512.max`
     */
    function test_mul() public {
        HugeInt.Uint512 memory a = HugeInt.Uint512(69, 0);
        HugeInt.Uint512 memory b = HugeInt.Uint512(42, 0);
        HugeInt.Uint512 memory res = HugeInt.mul(a, b);
        assertEq(res.lo, 2898, "69*42: lo");
        assertEq(res.hi, 0, "69*42: hi");

        a = HugeInt.Uint512(1, 0);
        b = HugeInt.Uint512(0, 0);
        res = HugeInt.mul(a, b);
        assertEq(res.lo, 0, "1*0: lo");
        assertEq(res.hi, 0, "1*0: hi");

        a = HugeInt.Uint512(type(uint256).max, 0);
        b = HugeInt.Uint512(1, 1);
        res = HugeInt.mul(a, b);
        assertEq(res.lo, type(uint256).max, "uint256.max*(uint256.max+2): lo");
        assertEq(res.hi, type(uint256).max, "uint256.max*(uint256.max+2): hi");
    }

    /**
     * @custom:scenario Reverting when overflow occurs
     * @custom:given Two 512-bit unsigned integers, the product of which overflows 512 bits
     * @custom:when The `mul` function is called with `uint512.max` and 2
     * @custom:or The `mul` function is called with `2^256` and `2^256`
     * @custom:or The `mul` function is called with `uint512.max` and `uint512.max/2`
     * @custom:then The transaction reverts
     */
    function test_RevertWhen_mulOverflow() public {
        HugeInt.Uint512 memory a = HugeInt.Uint512(type(uint256).max, type(uint256).max);
        HugeInt.Uint512 memory b = HugeInt.Uint512(2, 0);
        vm.expectRevert(HugeInt.HugeIntMulOverflow.selector);
        handler.mul(a, b);

        a = HugeInt.Uint512(0, 1);
        b = HugeInt.Uint512(0, 1);
        vm.expectRevert(HugeInt.HugeIntMulOverflow.selector);
        handler.mul(a, b);

        a = HugeInt.Uint512(type(uint256).max, type(uint256).max);
        b = HugeInt.Uint512(type(uint256).max, type(uint256).max / 2);
        vm.expectRevert(HugeInt.HugeIntMulOverflow.selector);
        handler.mul(a, b);
    }
}

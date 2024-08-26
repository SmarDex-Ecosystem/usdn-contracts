// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { HugeUintFixture } from "./utils/Fixtures.sol";

import { HugeUint } from "../../../src/libraries/HugeUint.sol";

/**
 * @custom:feature Unit tests for the `div(Uint512,uint256)` function of the `HugeUint` uint512 library
 */
contract TestHugeUintDiv256 is HugeUintFixture {
    function setUp() public override {
        super.setUp();
    }

    /**
     * @custom:scenario Testing the `div` function
     * @custom:given A 512-bit unsigned integer and a 256-bit unsigned integer
     * @custom:and The result of the division does not overflow 256 bits
     * @custom:when The `div` function is called with 1 and 10
     * @custom:then The result is equal to 0
     * @custom:when The `div` function is called with `uint256.max` and 1
     * @custom:then The result is equal to `uint256.max`
     * @custom:when The `div` function is called with `<uint256.max - 1, uint256.max>` and `uint256.max`
     * @custom:then The result is equal to `uint256.max`
     */
    function test_div() public view {
        HugeUint.Uint512 memory a = HugeUint.Uint512(0, 1);
        uint256 b = 10;
        uint256 res = handler.div(a, b);
        assertEq(res, 0, "1/10");

        a = HugeUint.Uint512(0, type(uint256).max);
        b = 1;
        res = handler.div(a, b);
        assertEq(res, type(uint256).max, "uint256.max/1");

        a = HugeUint.Uint512(type(uint256).max - 1, type(uint256).max);
        b = type(uint256).max;
        res = handler.div(a, b);
        assertEq(res, type(uint256).max, "0xfff...e|fff...fff/uint256.max");
    }

    /**
     * @custom:scenario Reverting when division failed
     * @custom:when The `div` function is called with `uint512.max` and `uint256.max`
     * @custom:or The `div` function is called with `uint512.max` and 1
     * @custom:or The `div` function is called with `<uint256.max, 1>` and 0
     * @custom:or The `div` function is called with 1 and 0
     * @custom:then The function reverts with `HugeUintDivisionFailed`
     */
    function test_RevertWhen_divOverflow() public {
        HugeUint.Uint512 memory a = HugeUint.Uint512(type(uint256).max, type(uint256).max);
        uint256 b = type(uint256).max;
        vm.expectRevert(HugeUint.HugeUintDivisionFailed.selector);
        handler.div(a, b);

        a = HugeUint.Uint512(type(uint256).max, type(uint256).max);
        b = 1;
        vm.expectRevert(HugeUint.HugeUintDivisionFailed.selector);
        handler.div(a, b);

        a = HugeUint.Uint512(type(uint256).max, 1);
        b = 0;
        vm.expectRevert(HugeUint.HugeUintDivisionFailed.selector);
        handler.div(a, b);

        a = HugeUint.Uint512(0, 1);
        b = 0;
        vm.expectRevert(HugeUint.HugeUintDivisionFailed.selector);
        handler.div(a, b);
    }
}

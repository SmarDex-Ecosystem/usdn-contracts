// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { HugeUintFixture } from "./utils/Fixtures.sol";

import { HugeUint } from "../../../src/libraries/HugeUint.sol";

/**
 * @custom:feature Unit tests for the `div(Uint512,Uint512)` function of the `HugeUint` uint512 library
 */
contract TestHugeUintDiv512 is HugeUintFixture {
    function setUp() public override {
        super.setUp();
    }

    /**
     * @custom:scenario Testing the `div` function
     * @custom:given Two 512-bit unsigned integers which division does not overflow 256 bits
     * @custom:when The `div` function is called with 69 and 42
     * @custom:then The result is equal to 1
     * @custom:when The `div` function is called with 1 and `2*uint256.max`
     * @custom:then The result is equal to 0
     * @custom:when The `div` function is called with `2*uint256.max` and 2
     * @custom:then The result is equal to `uint256.max`
     * @custom:when The `div` function is called with `uint512.max` and `2^256`
     * @custom:then The result is equal to `uint256.max` (note that this is larger than uint256.max, but does not
     * overflow due to rounding down)
     */
    function test_div() public view {
        HugeUint.Uint512 memory a = HugeUint.Uint512(0, 69);
        HugeUint.Uint512 memory b = HugeUint.Uint512(0, 42);
        uint256 res = HugeUint.div(a, b);
        assertEq(res, 1, "69/42");

        a = HugeUint.Uint512(0, 1);
        b = HugeUint.Uint512(1, type(uint256).max);
        res = HugeUint.div(a, b);
        assertEq(res, 0, "1/(uint256.max*2)");

        a = HugeUint.Uint512(1, type(uint256).max);
        b = HugeUint.Uint512(0, 2);
        res = HugeUint.div(a, b);
        assertEq(res, type(uint256).max, "uint256.max*2/2");

        a = HugeUint.Uint512(type(uint256).max, type(uint256).max);
        b = HugeUint.Uint512(1, 0);
        res = handler.div(a, b);
        assertEq(res, type(uint256).max, "uint512.max/2^256");
    }

    /**
     * @custom:scenario Reverting when division failed
     * @custom:given Two 512-bit unsigned integers which division overflows 256 bits or the divisor is 0
     * @custom:when The `div` function is called with `69` and 0
     * @custom:or The `div` function is called with `uint512.max` and 0
     * @custom:or The `div` function is called with `uint512.max` and `uint256.max`
     * @custom:then The function reverts with `HugeUintDivisionFailed`
     */
    function test_RevertWhen_div() public {
        HugeUint.Uint512 memory a = HugeUint.Uint512(0, 69);
        HugeUint.Uint512 memory b = HugeUint.Uint512(0, 0);
        vm.expectRevert(HugeUint.HugeUintDivisionFailed.selector);
        HugeUint.div(a, b);

        a = HugeUint.Uint512(type(uint256).max, type(uint256).max);
        b = HugeUint.Uint512(0, 0);
        vm.expectRevert(HugeUint.HugeUintDivisionFailed.selector);
        HugeUint.div(a, b);

        a = HugeUint.Uint512(type(uint256).max, type(uint256).max);
        b = HugeUint.Uint512(0, type(uint256).max);
        vm.expectRevert(HugeUint.HugeUintDivisionFailed.selector);
        HugeUint.div(a, b);
    }
}

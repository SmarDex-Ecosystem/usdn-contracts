// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { HugeUintFixture } from "./utils/Fixtures.sol";

import { HugeUint } from "../../../src/libraries/HugeUint.sol";

/**
 * @custom:feature Unit tests for the `add` function of the `HugeUint` uint512 library
 */
contract TestHugeUintAdd is HugeUintFixture {
    function setUp() public override {
        super.setUp();
    }

    /**
     * @custom:scenario Testing the `add` function
     * @custom:given Two 512-bit unsigned integers, the sum of which does not overflow 512 bits
     * @custom:when The `add` function is called with the 42 and 420
     * @custom:then The result is equal to 462
     * @custom:when The `add` function is called with `uint512.max/2` and `uint512.max/2`
     * @custom:then The result is equal to `uint512.max - 1`
     */
    function test_add() public view {
        HugeUint.Uint512 memory a = HugeUint.wrap(42);
        HugeUint.Uint512 memory b = HugeUint.wrap(420);
        HugeUint.Uint512 memory res = handler.add(a, b);
        assertEq(res.lo, 462, "42+420: lo");
        assertEq(res.hi, 0, "42+420: hi");

        a = HugeUint.Uint512(type(uint256).max / 2, type(uint256).max);
        b = HugeUint.Uint512(type(uint256).max / 2, type(uint256).max);
        res = handler.add(a, b);
        assertEq(res.lo, type(uint256).max - 1, "uint256.max/2: lo");
        assertEq(res.hi, type(uint256).max, "uint256.max/2: hi");
    }

    /**
     * @custom:scenario Reverting when overflow occurs
     * @custom:given Two 512-bit unsigned integers, the sum of which overflows 512 bits
     * @custom:when The `add` function is called with `uint512.max` and 1
     * @custom:or The `add` function is called with `uint512.max/2` and `uint512.max/2 + 1`
     * @custom:then The transaction reverts
     */
    function test_RevertWhen_addOverflow() public {
        HugeUint.Uint512 memory a = HugeUint.Uint512(type(uint256).max, type(uint256).max);
        HugeUint.Uint512 memory b = HugeUint.Uint512(0, 1);
        vm.expectRevert(HugeUint.HugeUintAddOverflow.selector);
        handler.add(a, b);

        a = HugeUint.Uint512(type(uint256).max / 2, type(uint256).max);
        b = HugeUint.Uint512(type(uint256).max / 2 + 1, type(uint256).max);
        vm.expectRevert(HugeUint.HugeUintAddOverflow.selector);
        handler.add(a, b);
    }
}

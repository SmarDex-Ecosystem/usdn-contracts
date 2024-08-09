// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { HugeUintFixture } from "./utils/Fixtures.sol";

import { HugeUint } from "../../../src/libraries/HugeUint.sol";

/**
 * @custom:feature Unit tests for the `mul(uint256,uint256)` function of the `HugeUint` uint512 library
 */
contract TestHugeUintMul256 is HugeUintFixture {
    function setUp() public override {
        super.setUp();
    }

    /**
     * @custom:scenario Testing the `mul` function
     * @custom:given Two 256-bit unsigned integers
     * @custom:when The `mul` function is called with 42 and 420
     * @custom:then The result is equal to 17640
     * @custom:when The `mul` function is called with `uint256.max` and `uint256.max`
     * @custom:then The result is equal to 0xfff..e|000..1 ((uint256.max - 1) * 2^256 + 1)
     * @custom:when The `mul` function is called with 0 and 1
     * @custom:then The result is equal to 0
     */
    function test_mul() public view {
        uint256 a = 42;
        uint256 b = 420;
        HugeUint.Uint512 memory res = handler.mul(a, b);
        assertEq(res.lo, 42 * 420, "42*420: lo");
        assertEq(res.hi, 0, "42*420: hi");

        a = type(uint256).max;
        b = type(uint256).max;
        res = handler.mul(a, b);
        assertEq(res.lo, 1, "uint256.max*uint256.max: lo");
        assertEq(res.hi, type(uint256).max - 1, "uint256.max*uint256.max: hi");

        a = 0;
        b = 1;
        res = handler.mul(a, b);
        assertEq(res.lo, 0, "0*1: lo");
        assertEq(res.hi, 0, "0*1: hi");
    }
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { HugeIntFixture } from "test/unit/HugeInt/utils/Fixtures.sol";

import { HugeInt } from "src/libraries/HugeInt.sol";

/**
 * @custom:feature Unit tests for the `add` function of the `HugeInt` uint512 library
 */
contract TestHugeIntAdd is HugeIntFixture {
    function setUp() public override {
        super.setUp();
    }

    function test_add() public {
        HugeInt.Uint512 memory a = HugeInt.wrap(42);
        HugeInt.Uint512 memory b = HugeInt.wrap(420);
        HugeInt.Uint512 memory res = handler.add(a, b);
        assertEq(res.lo, 462, "42+420: lo");
        assertEq(res.hi, 0, "42+420: hi");

        a = HugeInt.Uint512(type(uint256).max, type(uint256).max / 2);
        b = HugeInt.Uint512(type(uint256).max, type(uint256).max / 2);
        res = handler.add(a, b);
        assertEq(res.lo, type(uint256).max - 1, "uint256.max/2: lo");
        assertEq(res.hi, type(uint256).max, "uint256.max/2: hi");
    }

    function test_RevertWhen_addOverflow() public {
        HugeInt.Uint512 memory a = HugeInt.Uint512(type(uint256).max, type(uint256).max);
        HugeInt.Uint512 memory b = HugeInt.Uint512(0, 1);
        vm.expectRevert(HugeInt.HugeIntAddOverflow.selector);
        handler.add(a, b);

        a = HugeInt.Uint512(type(uint256).max, type(uint256).max / 2);
        b = HugeInt.Uint512(type(uint256).max, type(uint256).max / 2 + 1);
        vm.expectRevert(HugeInt.HugeIntAddOverflow.selector);
        handler.add(a, b);
    }
}

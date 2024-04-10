// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { HugeIntFixture } from "test/unit/HugeInt/utils/Fixtures.sol";

import { HugeInt } from "src/libraries/HugeInt.sol";

/**
 * @custom:feature Fuzzing tests for the `HugeInt` uint512 library
 */
contract TestHugeIntFuzzing is HugeIntFixture {
    function setUp() public override {
        super.setUp();
    }

    function testFuzz_FFIAdd(uint256 a0, uint256 a1, uint256 b0, uint256 b1) public {
        bytes memory a = abi.encodePacked(a1, a0);
        bytes memory b = abi.encodePacked(b1, b0);
        bytes memory result = vmFFIRustCommand("huge-int-add", vm.toString(a), vm.toString(b));
        (uint256 res0, uint256 res1) = abi.decode(result, (uint256, uint256));
        HugeInt.Uint512 memory res = handler.add(HugeInt.Uint512(a0, a1), HugeInt.Uint512(b0, b1));
        assertEq(res.lsb, res0, "lsb");
        assertEq(res.msb, res1, "msb");
    }

    function testFuzz_FFISub(uint256 a0, uint256 a1, uint256 b0, uint256 b1) public {
        bytes memory a = abi.encodePacked(a1, a0);
        bytes memory b = abi.encodePacked(b1, b0);
        bytes memory result = vmFFIRustCommand("huge-int-sub", vm.toString(a), vm.toString(b));
        (uint256 res0, uint256 res1) = abi.decode(result, (uint256, uint256));
        HugeInt.Uint512 memory res = handler.sub(HugeInt.Uint512(a0, a1), HugeInt.Uint512(b0, b1));
        assertEq(res.lsb, res0, "lsb");
        assertEq(res.msb, res1, "msb");
    }

    function testFuzz_FFIMul(uint256 a, uint256 b) public {
        bytes memory result = vmFFIRustCommand("huge-int-mul", vm.toString(a), vm.toString(b));
        (uint256 res0, uint256 res1) = abi.decode(result, (uint256, uint256));
        HugeInt.Uint512 memory res = handler.mul(a, b);
        assertEq(res.lsb, res0, "lsb");
        assertEq(res.msb, res1, "msb");
    }

    function testFuzz_FFIDiv256(uint256 a0, uint256 a1, uint256 b) public {
        vm.assume(b > 0);
        vm.assume(a1 < type(uint256).max);
        b = bound(b, a1 + 1, type(uint256).max);
        bytes memory a = abi.encodePacked(a1, a0);
        bytes memory result = vmFFIRustCommand("huge-int-div256", vm.toString(a), vm.toString(b));
        uint256 ref = abi.decode(result, (uint256));
        uint256 res = handler.div256(HugeInt.Uint512(a0, a1), b);
        assertEq(res, ref);
    }
}

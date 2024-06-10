// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { Permit2TokenBitfieldFixture } from "test/unit/Permit2TokenBitfield/utils/Fixtures.sol";

import { Permit2TokenBitfield } from "src/libraries/Permit2TokenBitfield.sol";

/// @custom:feature Test functions in `Permit2TokenBitfield`
contract TestPermit2TokenBitfield is Permit2TokenBitfieldFixture {
    function setUp() public override {
        super.setUp();
    }

    function test_asset() public {
        assertTrue(handler.useForAsset(Permit2TokenBitfield.Bitfield.wrap(1)), "0b0000_0001");
        assertTrue(handler.useForAsset(Permit2TokenBitfield.Bitfield.wrap(255)), "uint8.max");
        assertFalse(handler.useForAsset(Permit2TokenBitfield.Bitfield.wrap(0)), "0");
        assertFalse(handler.useForAsset(Permit2TokenBitfield.Bitfield.wrap(~uint8(1))), "0b1111_1110");
    }

    function test_usdn() public {
        assertTrue(handler.useForUsdn(Permit2TokenBitfield.Bitfield.wrap(1 << 1)), "0b0000_0010");
        assertTrue(handler.useForUsdn(Permit2TokenBitfield.Bitfield.wrap(255)), "uint8.max");
        assertFalse(handler.useForUsdn(Permit2TokenBitfield.Bitfield.wrap(0)), "0");
        assertFalse(handler.useForUsdn(Permit2TokenBitfield.Bitfield.wrap(~uint8(1 << 1))), "0b1111_1101");
    }

    function test_sdex() public {
        assertTrue(handler.useForSdex(Permit2TokenBitfield.Bitfield.wrap(1 << 2)), "0b0000_0100");
        assertTrue(handler.useForSdex(Permit2TokenBitfield.Bitfield.wrap(255)), "uint8.max");
        assertFalse(handler.useForSdex(Permit2TokenBitfield.Bitfield.wrap(0)), "0");
        assertFalse(handler.useForSdex(Permit2TokenBitfield.Bitfield.wrap(~uint8(1 << 2))), "0b1111_11011");
    }

    function testFuzz_asset(uint8 bitfield) public {
        bool expectedResult = bitfield & 1 == 1;
        assertEq(handler.useForAsset(Permit2TokenBitfield.Bitfield.wrap(bitfield)), expectedResult);
    }

    function testFuzz_usdn(uint8 bitfield) public {
        bool expectedResult = bitfield >> 1 & 1 == 1;
        assertEq(handler.useForUsdn(Permit2TokenBitfield.Bitfield.wrap(bitfield)), expectedResult);
    }

    function testFuzz_sdex(uint8 bitfield) public {
        bool expectedResult = bitfield >> 2 & 1 == 1;
        assertEq(handler.useForSdex(Permit2TokenBitfield.Bitfield.wrap(bitfield)), expectedResult);
    }
}

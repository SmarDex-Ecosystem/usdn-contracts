// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { Permit2TokenBitfieldFixture } from "./utils/Fixtures.sol";

import { Permit2TokenBitfield } from "../../../src/libraries/Permit2TokenBitfield.sol";

/// @custom:feature Test functions in `Permit2TokenBitfield`
contract TestPermit2TokenBitfield is Permit2TokenBitfieldFixture {
    function setUp() public override {
        super.setUp();
    }

    /**
     * @custom:scenario Test the `useForAsset` function
     * @custom:when The bitfield is 0b0000_0001
     * @custom:or The bitfield is uint8.max
     * @custom:then The function should return true
     * @custom:when The bitfield is 0
     * @custom:or The bitfield is 0b1111_1110
     * @custom:then The function should return false
     */
    function test_asset() public view {
        assertTrue(handler.useForAsset(Permit2TokenBitfield.Bitfield.wrap(1)), "0b0000_0001");
        assertTrue(handler.useForAsset(Permit2TokenBitfield.Bitfield.wrap(255)), "uint8.max");
        assertFalse(handler.useForAsset(Permit2TokenBitfield.Bitfield.wrap(0)), "0");
        assertFalse(handler.useForAsset(Permit2TokenBitfield.Bitfield.wrap(~uint8(1))), "0b1111_1110");
    }

    /**
     * @custom:scenario Test the `useForSdex` function
     * @custom:when The bitfield is 0b0000_0010
     * @custom:or The bitfield is uint8.max
     * @custom:then The function should return true
     * @custom:when The bitfield is 0
     * @custom:or The bitfield is 0b1111_11101
     * @custom:then The function should return false
     */
    function test_sdex() public view {
        assertTrue(handler.useForSdex(Permit2TokenBitfield.Bitfield.wrap(1 << 1)), "0b0000_0010");
        assertTrue(handler.useForSdex(Permit2TokenBitfield.Bitfield.wrap(255)), "uint8.max");
        assertFalse(handler.useForSdex(Permit2TokenBitfield.Bitfield.wrap(0)), "0");
        assertFalse(handler.useForSdex(Permit2TokenBitfield.Bitfield.wrap(~uint8(1 << 1))), "0b1111_1101");
    }

    /**
     * @custom:scenario Test the `useForAsset` function for a random bitfield
     * @custom:given A random bitfield
     * @custom:when The function is called with a bitfield which has its first bit set
     * @custom:then The function should return true
     * @custom:when The function is called with a bitfield which has its first bit unset
     * @custom:then The function should return false
     * @param bitfield The bitfield
     */
    function testFuzz_asset(uint8 bitfield) public view {
        bool expectedResult = bitfield & 1 == 1;
        assertEq(handler.useForAsset(Permit2TokenBitfield.Bitfield.wrap(bitfield)), expectedResult);
    }

    /**
     * @custom:scenario Test the `useForSdex` function for a random bitfield
     * @custom:given A random bitfield
     * @custom:when The function is called with a bitfield which has its second bit set
     * @custom:then The function should return true
     * @custom:when The function is called with a bitfield which has its second bit unset
     * @custom:then The function should return false
     * @param bitfield The bitfield
     */
    function testFuzz_sdex(uint8 bitfield) public view {
        bool expectedResult = bitfield >> 1 & 1 == 1;
        assertEq(handler.useForSdex(Permit2TokenBitfield.Bitfield.wrap(bitfield)), expectedResult);
    }
}

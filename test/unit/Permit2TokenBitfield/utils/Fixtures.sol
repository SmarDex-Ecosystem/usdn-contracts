// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { console2 } from "forge-std/Test.sol";

import { BaseFixture } from "test/utils/Fixtures.sol";
import { Permit2TokenBitfieldHandler } from "test/unit/Permit2TokenBitfield/utils/Handler.sol";

/**
 * @title Permit2TokenBitfieldFixture
 * @dev Utils for testing Permit2TokenBitfield.sol
 */
contract Permit2TokenBitfieldFixture is BaseFixture {
    Permit2TokenBitfieldHandler public handler; // wrapper to get gas usage report

    function setUp() public virtual {
        handler = new Permit2TokenBitfieldHandler();
    }

    // force ignore from coverage report
    // until https://github.com/foundry-rs/foundry/issues/2988 is fixed
    function test() public override { }
}

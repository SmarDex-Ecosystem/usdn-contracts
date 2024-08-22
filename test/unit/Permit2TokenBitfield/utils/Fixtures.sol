// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { BaseFixture } from "../../../utils/Fixtures.sol";
import { Permit2TokenBitfieldHandler } from "../utils/Handler.sol";

/**
 * @title Permit2TokenBitfieldFixture
 * @dev Utils for testing Permit2TokenBitfield.sol
 */
contract Permit2TokenBitfieldFixture is BaseFixture {
    Permit2TokenBitfieldHandler public handler; // wrapper to get gas usage report

    function setUp() public virtual {
        handler = new Permit2TokenBitfieldHandler();
    }
}

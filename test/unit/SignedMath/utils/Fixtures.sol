// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { BaseFixture } from "../../../utils/Fixtures.sol";
import { SignedMathHandler } from "../utils/Handler.sol";

/**
 * @title SignedMathFixture
 * @dev Utils for testing SignedMath.sol
 */
contract SignedMathFixture is BaseFixture {
    SignedMathHandler public handler; // wrapper to get gas usage report

    function setUp() public virtual {
        handler = new SignedMathHandler();
    }
}

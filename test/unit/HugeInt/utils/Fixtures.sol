// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { BaseFixture } from "test/utils/Fixtures.sol";
import { HugeIntHandler } from "test/unit/HugeInt/utils/Handler.sol";

/**
 * @title HugeIntFixture
 * @dev Utils for testing HugeInt.sol
 */
contract HugeIntFixture is BaseFixture {
    HugeIntHandler public handler; // wrapper to get gas usage report

    function setUp() public virtual {
        handler = new HugeIntHandler();
    }

    // force ignore from coverage report
    // until https://github.com/foundry-rs/foundry/issues/2988 is fixed
    function test() public override { }
}

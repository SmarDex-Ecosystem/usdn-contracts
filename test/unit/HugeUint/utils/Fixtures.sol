// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { BaseFixture } from "../../../utils/Fixtures.sol";
import { HugeUintHandler } from "../utils/Handler.sol";

/**
 * @title HugeUintFixture
 * @dev Utils for testing HugeUint.sol
 */
contract HugeUintFixture is BaseFixture {
    HugeUintHandler public handler; // wrapper to get gas usage report

    function setUp() public virtual {
        handler = new HugeUintHandler();
    }
}

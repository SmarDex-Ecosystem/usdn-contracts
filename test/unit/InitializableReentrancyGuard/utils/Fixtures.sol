// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import { BaseFixture } from "test/utils/Fixtures.sol";

import { InitializableReentrancyGuardHandler } from "test/unit/InitializableReentrancyGuard/utils/Handler.sol";

/**
 * @title InitializableReentrancyGuardFixtures
 * @dev Utils for testing InitializableReentrancyGuard.sol
 */
contract InitializableReentrancyGuardFixtures is BaseFixture {
    InitializableReentrancyGuardHandler public handler;

    function setUp() public virtual {
        handler = new InitializableReentrancyGuardHandler();

        // To have ether to send for reentrancy tests
        vm.deal(address(handler), 1);
    }

    // force ignore from coverage report
    // until https://github.com/foundry-rs/foundry/issues/2988 is fixed
    function test() public override { }
}

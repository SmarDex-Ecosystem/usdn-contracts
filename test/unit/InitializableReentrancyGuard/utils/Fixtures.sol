// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { BaseFixture } from "../../../utils/Fixtures.sol";

import { InitializableReentrancyGuardHandler } from "../utils/Handler.sol";

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
}

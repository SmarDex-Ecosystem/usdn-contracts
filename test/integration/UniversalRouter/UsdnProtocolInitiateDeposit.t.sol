// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { UniversalRouterBaseFixture } from "test/integration/UniversalRouter/utils/Fixtures.sol";

import { Commands } from "src/UniversalRouter/libraries/Commands.sol";

contract TestForkUniversalRouterInitiateDeposit is UniversalRouterBaseFixture {
    function setUp() public {
        _setUp();
    }

    function test_ForkInitiateDeposit() public {
        // commands
        bytes memory commands = abi.encodePacked(bytes1(uint8(Commands.INITIATE_DEPOSIT)));

        // inputs
        bytes[] memory inputs = new bytes[](1);
    }
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { ProtocolAction } from "src/interfaces/IOracleMiddleware.sol";

contract ActionsIntegrationTests {
    // action types for integration tests
    ProtocolAction[] public actions = [
        ProtocolAction.None,
        ProtocolAction.InitiateDeposit,
        ProtocolAction.ValidateDeposit,
        ProtocolAction.ValidateOpenPosition
    ];
}

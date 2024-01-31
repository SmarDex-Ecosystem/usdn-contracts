// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { ProtocolAction } from "src/interfaces/IOracleMiddleware.sol";

contract Actions {
    // all action types
    ProtocolAction[] public actions = [
        ProtocolAction.None,
        ProtocolAction.Initialize,
        ProtocolAction.InitiateDeposit,
        ProtocolAction.ValidateDeposit,
        ProtocolAction.InitiateWithdrawal,
        ProtocolAction.ValidateWithdrawal,
        ProtocolAction.InitiateOpenPosition,
        ProtocolAction.ValidateOpenPosition,
        ProtocolAction.InitiateClosePosition,
        ProtocolAction.ValidateClosePosition,
        ProtocolAction.Liquidation
    ];
}

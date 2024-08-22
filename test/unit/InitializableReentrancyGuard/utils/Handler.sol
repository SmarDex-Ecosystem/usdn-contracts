// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { InitializableReentrancyGuard } from "../../../../src/utils/InitializableReentrancyGuard.sol";

/**
 * @title InitializableReentrancyGuardHandler
 * @dev Wrapper to help test InitializableReentrancyGuard
 */
contract InitializableReentrancyGuardHandler is InitializableReentrancyGuard {
    function initialize() external protocolInitializer { }

    function func_initializedAndNonReentrant() external initializedAndNonReentrant {
        // gives a reentrancy opportunity
        (bool success,) = msg.sender.call{ value: 1 }("");
        require(success, "transfer failed");
    }

    function i_checkUninitialized() external view {
        return _checkUninitialized();
    }
}

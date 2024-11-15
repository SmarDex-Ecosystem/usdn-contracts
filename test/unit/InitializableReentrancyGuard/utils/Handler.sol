// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { InitializableReentrancyGuard } from "../../../../src/utils/InitializableReentrancyGuard.sol";
import { ReentrancyGuardTransientUpgradeable } from
    "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardTransientUpgradeable.sol";

/**
 * @title InitializableReentrancyGuardHandler
 * @dev Wrapper to help test InitializableReentrancyGuard
 */
contract InitializableReentrancyGuardHandler is InitializableReentrancyGuard, ReentrancyGuardTransientUpgradeable {
    function initialize() external protocolInitializer { }

    function func_initializedAndNonReentrant() external initializedAndNonReentrant nonReentrant {
        // gives a reentrancy opportunity
        (bool success,) = msg.sender.call{ value: 1 }("");
        require(success, "transfer failed");
    }

    function i_checkUninitialized() external view {
        return _checkUninitialized();
    }

    function i_getStorageStatus() external pure returns (StorageStatus memory) {
        return _getStorageStatus();
    }

    function i_reentrancyGuardEntered() external view returns (bool) {
        return _reentrancyGuardEntered();
    }
}

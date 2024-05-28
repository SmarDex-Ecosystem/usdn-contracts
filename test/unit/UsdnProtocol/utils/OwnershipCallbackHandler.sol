// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { IEventsErrors } from "test/utils/IEventsErrors.sol";

import { IOwnershipCallback } from "src/interfaces/UsdnProtocol/IOwnershipCallback.sol";
import { PositionId } from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";

/// @dev Mock handler for ownership transfer
contract OwnershipCallbackHandler is IOwnershipCallback, IEventsErrors {
    bool public shouldFail;

    function ownershipCallback(address oldOwner, PositionId calldata posId) external {
        if (shouldFail) {
            revert OwnershipCallbackFailure();
        }
        emit TestOwnershipCallback(oldOwner, posId);
    }

    function setShouldFail(bool newValue) external {
        shouldFail = newValue;
    }
}

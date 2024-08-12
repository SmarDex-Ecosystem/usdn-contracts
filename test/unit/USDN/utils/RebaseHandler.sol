// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { IEventsErrors } from "../../../utils/IEventsErrors.sol";

import { IRebaseCallback } from "../../../../src/interfaces/Usdn/IRebaseCallback.sol";

/// @dev Mock rebase handler for testing
contract RebaseHandler is IRebaseCallback, IEventsErrors {
    bool public shouldFail;

    function rebaseCallback(uint256 oldDivisor, uint256 newDivisor) external returns (bytes memory result_) {
        if (shouldFail) {
            revert RebaseHandlerFailure();
        }
        emit TestCallback();
        return abi.encode(oldDivisor, newDivisor);
    }

    function setShouldFail(bool newValue) external {
        shouldFail = newValue;
    }
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { IRebaseCallback } from "src/interfaces/Usdn/IRebaseCallback.sol";

/// @dev Mock rebase handler for testing
contract RebaseHandler is IRebaseCallback {
    event TestCallback();

    function rebaseCallback(uint256 oldDivisor, uint256 newDivisor) external returns (bytes memory result_) {
        emit TestCallback();
        return abi.encode(oldDivisor, newDivisor);
    }
}

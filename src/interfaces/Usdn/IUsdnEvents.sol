// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import { IRebaseCallback } from "src/interfaces/Usdn/IRebaseCallback.sol";

/**
 * @title Events for the USDN token contract
 * @notice Contains all custom events emitted by the USDN token contract (omitting events from OpenZeppelin)
 */
interface IUsdnEvents {
    /**
     * @notice Emitted when the divisor is adjusted to rebase the user balances and total supply
     * @param oldDivisor divisor before rebase
     * @param newDivisor divisor after rebase
     */
    event Rebase(uint256 oldDivisor, uint256 newDivisor);

    /**
     * @notice Emitted when the rebase handler address is updated
     * @param newHandler The address of the new rebase handler
     */
    event RebaseHandlerUpdated(IRebaseCallback newHandler);
}

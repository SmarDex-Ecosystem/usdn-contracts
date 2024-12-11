// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import { IRebaseCallback } from "./IRebaseCallback.sol";

/**
 * @title Events for the USDN token contract
 * @notice Defines all custom events emitted by the USDN token contract.
 */
interface IUsdnEvents {
    /**
     * @notice The divisor was updated, emitted during a rebase.
     * @param oldDivisor The divisor value before the rebase.
     * @param newDivisor The new divisor value.
     */
    event Rebase(uint256 oldDivisor, uint256 newDivisor);

    /**
     * @notice The rebase handler address was updated.
     * @dev The rebase handler is a contract that is called when a rebase occurs.
     * @param newHandler The address of the new rebase handler contract.
     */
    event RebaseHandlerUpdated(IRebaseCallback newHandler);
}

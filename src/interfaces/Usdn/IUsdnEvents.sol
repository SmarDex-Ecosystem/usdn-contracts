// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.0;

/**
 * @title Events for the USDN token contract
 * @notice Contains all custom events emitted by the USDN token contract (omitting events from OpenZeppelin)
 */
interface IUsdnEvents {
    /**
     * @notice Emitted when the divisor is adjusted.
     * @param oldDivisor divisor before adjustment
     * @param newDivisor divisor after adjustment
     */
    event DivisorAdjusted(uint256 oldDivisor, uint256 newDivisor);
}

// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.0;

/**
 * @title Events for the USDN token contract
 * @notice Contains all custom events emitted by the USDN token contract (omitting events from OpenZeppelin)
 */
interface IUsdnEvents {
    /**
     * @notice Emitted when the divisor is adjusted to rebase the user balances and total supply.
     * @param oldDivisor divisor before rebase
     * @param newDivisor divisor after rebase
     */
    event Rebase(uint256 oldDivisor, uint256 newDivisor);
}

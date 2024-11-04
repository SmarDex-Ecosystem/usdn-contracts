// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

/**
 * @title Errors for the WUSDN token contract
 * @notice Contains all custom errors emitted by the WUSDN token contract (omitting errors from OpenZeppelin)
 */
interface IWusdnErrors {
    /**
     * @dev Indicates that the user has insufficient USDN balance to wrap `usdnAmount`
     * @param usdnAmount The amount of USDN the user attempted to wrap
     */
    error WusdnInsufficientBalance(uint256 usdnAmount);

    /**
     * @dev Indicates that the user is attempting to wrap an amount of USDN shares
     * that is lower than the minimum SHARES_RATIO required by the WUSDN token
     * This results in a wrapped amount of zero WUSDN
     */
    error WusdnWrapZeroAmount();
}

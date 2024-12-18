// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

/**
 * @title Errors For The WUSDN Token Contract
 * @notice Defines all custom errors emitted by the WUSDN token contract.
 */
interface IWusdnErrors {
    /**
     * @dev The user has insufficient USDN balance to wrap the given `usdnAmount`.
     * @param usdnAmount The amount of USDN the user attempted to wrap.
     */
    error WusdnInsufficientBalance(uint256 usdnAmount);

    /**
     * @dev The user is attempting to wrap an amount of USDN shares that is lower than the minimum:
     * {IWusdn.SHARES_RATIO}, required by the WUSDN token. This results in a wrapped amount of zero WUSDN.
     */
    error WusdnWrapZeroAmount();
}

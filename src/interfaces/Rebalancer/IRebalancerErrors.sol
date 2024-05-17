// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.0;

interface IRebalancerErrors {
    /// @dev The user assets are used in a position
    error RebalancerUserNotPending();

    /// @dev The `to` address is invalid
    error RebalancerInvalidAddressTo();

    /// @dev The amount of assets is invalid
    error RebalancerInvalidAmount();

    /// @dev The amount to withdraw is greater than the amount deposited
    error RebalancerWithdrawAmountTooLarge();

    /// @dev Indicates that the provided max leverage is invalid
    error RebalancerInvalidMaxLeverage();
}

// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.0;

interface IOrderManagerErrors {
    /// @dev The user assets are used   in a position
    error OrderManagerUserNotPending();

    /// @dev The `to` address is invalid
    error OrderManagerInvalidAddressTo();

    /// @dev The amount to withdraw is greater than the amount deposited
    error OrderManagerWithdrawAmountGreaterThanDeposited();
}

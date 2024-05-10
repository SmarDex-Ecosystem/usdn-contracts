// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.0;

interface IOrderManagerErrors {
    /// @dev The user funds are in a position
    error OrderManagerUserNotPending();

    /// @dev The `to` address is invalid
    error OrderManagerInvalidAddressTo();

    /// @dev There are not enough assets to be withdrawn
    error OrderManagerNotEnoughAssetsToWithdraw();
}

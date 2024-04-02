// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.0;

interface IOrderManagerErrors {
    /// @notice Indicates that the contract was not initialized.
    error OrderManagerNotInitialized();
    /// @notice Indicates that the provided tick is not a multiple of the tick spacing or outside of the limits.
    error OrderManagerInvalidTick(int24 tick);
    /// @notice Indicates that the current user tried to withdraw more assets than his deposits.
    error OrderManagerInsufficientFunds(int24 tick, address user, uint232 amountInTick, uint232 amountToWithdraw);
}

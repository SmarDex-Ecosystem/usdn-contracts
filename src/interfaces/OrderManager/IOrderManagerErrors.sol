// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.0;

interface IOrderManagerErrors {
    /// @notice Indicates that the contract was not initialized.
    error OrderManagerNotInitialized();

    /// @notice Indicates that the provided leverage is higher than the max leverage, or lower than the min leverage.
    error OrderManagerInvalidLeverage();

    /**
     * @notice Indicates that the provided tick is not a multiple of the tick spacing or outside of the limits.
     * @param tick The invalid tick.
     */
    error OrderManagerInvalidTick(int24 tick);

    /**
     * @notice Indicates that the current user tried to withdraw more assets than their deposits.
     * @param tick The tick to withdraw the funds from.
     * @param user The user the funds belong to.
     * @param amountInTick The amount available in the tick for the user.
     * @param amountToWithdraw The amount the user tried to withdraw.
     */
    error OrderManagerInsufficientFunds(int24 tick, address user, uint256 amountInTick, uint232 amountToWithdraw);

    /**
     * @notice Indicates that the caller is not the usdn protocol.
     * @param caller The address of the caller.
     */
    error OrderManagerCallerIsNotUSDNProtocol(address caller);

    /**
     * @notice Indicates that the order is not pending and cannot be interacted with.
     * @param tick The tick the order is in.
     * @param tickVersion The version of the tick.
     */
    error OrderManagerOrderNotPending(int24 tick, uint256 tickVersion);
}

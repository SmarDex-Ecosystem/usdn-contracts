// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.0;

interface IOrderManagerErrors {
    /// @notice Indicates that the contract was not initialized.
    error OrderManagerNotInitialized();
    /// @notice Indicates that the provided tick is not a multiple of the tick spacing and is therefore invalid.
    error OrderManagerInvalidTick(int24 tick);
    /// @notice Indicates that the current user tried to manipulate the order of another user.
    error OrderManagerNoOrderForUserInTick(int24 tick, address user);
    /// @notice Indicates that the caller is not the usdn protocol.
    error OrderManagerCallerIsNotUSDNProtocol(address caller);
    /// @notice Indicates that the caller is not the usdn protocol.
    error OrderManagerUserAlreadyInTick(address caller, int24 tick, uint256 tickVersion);
}

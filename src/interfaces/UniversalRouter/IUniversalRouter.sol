// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

interface IUniversalRouter {
    /**
     * @notice Indicates that a required command has failed
     * @param commandIndex The index of the command that failed
     * @param message The error message
     */
    error ExecutionFailed(uint256 commandIndex, bytes message);

    /// @notice Thrown when attempting to send ETH directly to the contract
    error ETHNotAccepted();

    /// @notice Thrown when executing commands with an expired deadline
    error TransactionDeadlinePassed();

    /// @notice Thrown when attempting to execute commands and an incorrect number of inputs are provided
    error LengthMismatch();

    /**
     * @notice Executes encoded commands along with provided inputs. Reverts if the deadline has expired
     * @param commands A set of concatenated commands, each 1 byte in length
     * @param inputs An array of byte strings containing abi encoded inputs for each command
     * @param deadline The deadline by which the transaction must be executed
     */
    function execute(bytes calldata commands, bytes[] calldata inputs, uint256 deadline) external payable;

    /**
     * @notice Executes encoded commands along with provided inputs
     * @param commands A set of concatenated commands, each 1 byte in length
     * @param inputs An array of byte strings containing abi encoded inputs for each command
     */
    function execute(bytes calldata commands, bytes[] calldata inputs) external payable;
}

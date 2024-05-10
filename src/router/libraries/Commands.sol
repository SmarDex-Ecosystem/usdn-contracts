// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

/// @title Commands
/// @notice Command Flags used to decode commands
library Commands {
    // Masks to extract certain bits of commands
    bytes1 internal constant FLAG_ALLOW_REVERT = 0x80;
    bytes1 internal constant COMMAND_TYPE_MASK = 0x3f;

    // Command Types. Maximum supported command at this moment is 0x3f.

    // Command Types where value<0x08, executed in the first nested-if block
    uint256 constant V3_SWAP_EXACT_IN = 0x00;
    uint256 constant V3_SWAP_EXACT_OUT = 0x01;
    uint256 constant PERMIT2_TRANSFER_FROM = 0x02;
    uint256 constant PERMIT2_PERMIT_BATCH = 0x03;
    uint256 constant SWEEP = 0x04;
    uint256 constant TRANSFER = 0x05;
    uint256 constant PAY_PORTION = 0x06;
    // COMMAND_PLACEHOLDER = 0x07;

    // The commands are executed in nested if blocks to minimise gas consumption
    // The following constant defines one of the boundaries where the if blocks split commands
    uint256 constant FIRST_IF_BOUNDARY = 0x08;

    // Command Types where 0x08<=value<=0x0d, executed in the second nested-if block
    uint256 constant V2_SWAP_EXACT_IN = 0x08;
    uint256 constant V2_SWAP_EXACT_OUT = 0x09;
    uint256 constant PERMIT2_PERMIT = 0x0a;
    uint256 constant WRAP_ETH = 0x0b;
    uint256 constant UNWRAP_WETH = 0x0c;
    uint256 constant PERMIT2_TRANSFER_FROM_BATCH = 0x0d;
    // COMMAND_PLACEHOLDER = 0x0e;

    // The commands are executed in nested if blocks to minimise gas consumption
    // The following constant defines one of the boundaries where the if blocks split commands
    uint256 constant SECOND_IF_BOUNDARY = 0x10;

    // Command Types where 0x10<=value<0x19, executed in the third nested-if block
    uint256 constant INITIATE_DEPOSIT = 0x10;
    uint256 constant INITIATE_WITHDRAW = 0x11;
    uint256 constant INITIATE_OPEN = 0x12;
    uint256 constant INITIATE_CLOSE = 0x13;
    uint256 constant VALIDATE_DEPOSIT = 0x14;
    uint256 constant VALIDATE_WITHDRAW = 0x15;
    uint256 constant VALIDATE_OPEN = 0x16;
    uint256 constant VALIDATE_CLOSE = 0x17;
    uint256 constant LIQUIDATE = 0x18;
    uint256 constant VALIDATE_PENDING = 0x19;

    // The commands are executed in nested if blocks to minimise gas consumption
    // The following constant defines one of the boundaries where the if blocks split commands
    uint256 constant THIRD_IF_BOUNDARY = 0x1b;

    // Command Types where 0x1b<=value<=0x1f, executed in the final nested-if block
    uint256 constant WRAP_USDN = 0x1b;
    uint256 constant UNWRAP_WUSDN = 0x1c;
    uint256 constant WRAP_STETH = 0x1d;
    uint256 constant UNWRAP_WSTETH = 0x1e;
    // COMMAND_PLACEHOLDER = 0x1f;

    // The commands are executed in nested if blocks to minimise gas consumption
    // The following constant defines one of the boundaries where the if blocks split commands
    uint256 constant FOURTH_IF_BOUNDARY = 0x20;

    // Command Types where 0x20<=value
    uint256 constant SMARDEX_SWAP_EXACT_IN = 0x20;
    uint256 constant SMARDEX_SWAP_EXACT_OUT = 0x21;
    uint256 constant APPROVE_ERC20 = 0x22;
    // COMMAND_PLACEHOLDER for 0x23 to 0x3f (all unused)
}

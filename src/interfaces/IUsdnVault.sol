// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

interface IUsdnVault { }

/* -------------------------------------------------------------------------- */
/*                                   Structs                                  */
/* -------------------------------------------------------------------------- */

/// @dev 32 bytes packed struct representing a position waiting for a commitment.
///      It can be a short entry, a short exit, a long entry or a long exit.
/// NOTE: The leverage is 0 if the position is a short.
struct Position {
    uint40 leverage; // Max 1_099_511_627_775 (1_099 with 9 decimals)
    uint40 timestamp; // Max 1_099_511_627_775 (20/02/36812 01:36:15)
    bool isExit;
    bool validated;
    address user;
    uint128 amount;
    uint128 startPrice;
}

/// @dev 32 bytes packed struct representing the metadata of a position waiting
///      for a commitment.
struct PendingPositionMetadata {
    int24 tick;
    uint64 gasPrice;
    uint168 index;
}

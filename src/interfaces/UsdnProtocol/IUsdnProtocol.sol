// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

/* -------------------------------------------------------------------------- */
/*                                   Structs                                  */
/* -------------------------------------------------------------------------- */

/**
 * @notice Information about a user position (vault deposit or long).
 * @dev 32 bytes packed struct (256 bits). In case of a vault deposit, the leverage value is zero.
 */
struct Position {
    uint40 leverage; // Max 1_099_511_627_775 (1_099 with 9 decimals), zero for vault deposits
    uint40 timestamp; // Max 1_099_511_627_775 (36812-02-20 01:36:15)
    bool isExit;
    bool validated;
    address user;
    uint128 amount; // Max 340_282_366_920_938_463_463.374_607_431_768_211_455 wstETH
    uint128 startPrice; // Max 340_282_366_920_938_463_463.374_607_431_768_211_455 USD/wstETH
}

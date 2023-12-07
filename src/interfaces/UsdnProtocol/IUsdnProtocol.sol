// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

/* -------------------------------------------------------------------------- */
/*                              Structs and enums                             */
/* -------------------------------------------------------------------------- */

/**
 * @notice Information about a user position (vault deposit or long).
 * @dev 64 bytes packed struct (512 bits). In case of a vault deposit, the leverage value is zero.
 * @param leverage The leverage of the position (0 for vault deposits).
 * @param timestamp The timestamp of the position start.
 * @param isExit Whether the position is an exit position (true) or an entry position (false).
 * @param validated Whether the position has been validated by the user (true) or is pending (false).
 * @param user The user address.
 * @param amount The amount of the position.
 * @param startPrice The price of the asset at the position opening.
 */
struct Position {
    uint40 leverage; // 5 bytes. Max 1_099_511_627_775 (1_099 with 9 decimals), zero for vault deposits
    uint40 timestamp; // 5 bytes. Max 1_099_511_627_775 (36812-02-20 01:36:15)
    bool isExit; // 1 byte
    bool validated; // 1 byte
    address user; // 20 bytes
    uint128 amount; // 16 bytes. Max 340_282_366_920_938_463_463.374_607_431_768_211_455 wstETH or USDN
    uint128 startPrice; // 16 bytes. Max 340_282_366_920_938_463_463.374_607_431_768_211_455 USD/wstETH
}

/**
 * @notice The type of action for which the price is requested.
 * @param None No particular action.
 * @param InitiateDeposit The price is requested for a deposit action.
 * @param ValidateDeposit The price is requested to validate a deposit action.
 * @param InitiateWithdraw The price is requested for a withdraw action.
 * @param ValidateWithdraw The price is requested to validate a withdraw action.
 * @param InitiateOpenPosition The price is requested for an open position action.
 * @param ValidateOpenPosition The price is requested to validate an open position action.
 * @param InitiateClosePosition The price is requested for a close position action.
 * @param ValidateClosePosition The price is requested tovalidate a close position action.
 * @param Liquidation The price is requested for a liquidation action.
 */
enum ProtocolAction {
    None,
    InitiateDeposit,
    ValidateDeposit,
    InitiateWithdraw,
    ValidateWithdraw,
    InitiateOpenPosition,
    ValidateOpenPosition,
    InitiateClosePosition,
    ValidateClosePosition,
    Liquidation
}

/**
 * @notice A pending action.
 * @param action The type of action.
 * @param user The user address.
 * @param timestamp The timestamp of the action initiation.
 */
struct PendingAction {
    ProtocolAction action; // 1 byte
    address user; // 20 bytes
    uint40 timestamp; // 5 bytes
}

/* -------------------------------------------------------------------------- */
/*                                   Events                                   */
/* -------------------------------------------------------------------------- */

interface IUsdnProtocolEvents { }

/* -------------------------------------------------------------------------- */
/*                                   Errors                                   */
/* -------------------------------------------------------------------------- */

interface IUsdnProtocolErrors {
    /// @dev Indicates that the provided amount is zero
    error UsdnProtocolZeroAmount();

    /// @dev Indicates that the the token transfer didn't yield the expected balance change
    error UsdnProtocolIncompleteTransfer(uint256 effectiveBalance, uint256 expectedBalance);

    /// @dev Indicates that the user already has a pending action
    error UsdnProtocolPendingAction();

    /// @dev Indicates that the user has no pending action
    error UsdnProtocolNoPendingAction();
}

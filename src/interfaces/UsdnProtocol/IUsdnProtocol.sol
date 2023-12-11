// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

/* -------------------------------------------------------------------------- */
/*                              Structs and enums                             */
/* -------------------------------------------------------------------------- */

/**
 * @notice Information about a long user position.
 * @dev 64 bytes packed struct (512 bits)
 * @param leverage The leverage of the position (0 for vault deposits).
 * @param timestamp The timestamp of the position start.
 * @param isExit Whether the position is an exit position (true) or an entry position (false).
 * @param validated Whether the position has been validated by the user (true) or is pending (false).
 * @param user The user address.
 * @param amount The amount of the position.
 * @param startPrice The price of the asset at the position opening.
 */
struct Position {
    uint40 leverage; // 5 bytes. Max 1_099_511_627_775 (1_099 with 9 decimals)
    uint40 timestamp; // 5 bytes. Max 1_099_511_627_775 (36812-02-20 01:36:15)
    bool isExit; // 1 byte
    bool validated; // 1 byte
    address user; // 20 bytes
    uint128 amount; // 16 bytes. Max 340_282_366_920_938_463_463.374_607_431_768_211_455 wstETH
    uint128 startPrice; // 16 bytes. Max 340_282_366_920_938_463_463.374_607_431_768_211_455 USD/wstETH
}

/**
 * @notice All possible action types for the protocol.
 * @dev This is used for pending actions and to interact with the oracle middleware.
 * @param None No particular action.
 * @param InitiateDeposit Initiating a deposit action.
 * @param ValidateDeposit Validating a deposit action.
 * @param InitiateWithdrawal Initiating a withdraw action.
 * @param ValidateWithdrawal Validating a withdraw action.
 * @param InitiateOpenPosition Initiating an open position action.
 * @param ValidateOpenPosition Validating an open position action.
 * @param InitiateClosePosition Initiating a close position action.
 * @param ValidateClosePosition Validating a close position action.
 * @param Liquidation The price is requested for a liquidation action.
 */
enum ProtocolAction {
    None,
    InitiateDeposit,
    ValidateDeposit,
    InitiateWithdrawal,
    ValidateWithdrawal,
    InitiateOpenPosition,
    ValidateOpenPosition,
    InitiateClosePosition,
    ValidateClosePosition,
    Liquidation
}

/**
 * @notice A pending deposit action.
 */
struct PendingAction {
    ProtocolAction action; // 1 byte
    uint40 timestamp; // 5 bytes
    address user; // 20 bytes
    int24 tick; // 3 bytes, tick for open/close long
    uint256 amountOrIndex; // 32 bytes, amount for deposit/withdraw, or index inside the tick for open/close long
}

/* -------------------------------------------------------------------------- */
/*                                   Events                                   */
/* -------------------------------------------------------------------------- */

interface IUsdnProtocolEvents {
    /**
     * @notice Emitted when a user initiates a deposit.
     * @param user The user address.
     * @param amount The amount of asset that were deposited.
     */
    event InitiatedDeposit(address indexed user, uint256 amount);

    /**
     * @notice Emitted when a user validates a deposit.
     * @param user The user address.
     * @param amountDeposited The amount of asset that were deposited.
     * @param usdnMinted The amount of USDN that were minted.
     */
    event ValidatedDeposit(address indexed user, uint256 amountDeposited, uint256 usdnMinted);

    /**
     * @notice Emitted when a user initiates a withdrawal.
     * @param user The user address.
     * @param usdnAmount The amount of USDN that will be burned.
     */
    event InitiatedWithdrawal(address indexed user, uint256 usdnAmount);

    /**
     * @notice Emitted when a user validates a withdrawal.
     * @param user The user address.
     * @param amountWithdrawn The amount of asset that were withdrawn.
     * @param usdnBurned The amount of USDN that were burned.
     */
    event ValidatedWithdrawal(address indexed user, uint256 amountWithdrawn, uint256 usdnBurned);
}

/* -------------------------------------------------------------------------- */
/*                                   Errors                                   */
/* -------------------------------------------------------------------------- */

interface IUsdnProtocolErrors {
    /// @dev Indicates that the provided amount is zero
    error UsdnProtocolZeroAmount();

    /// @dev Indicates that the the token transfer didn't yield the expected balance change
    error UsdnProtocolIncompleteTransfer(address to, uint256 effectiveBalance, uint256 expectedBalance);

    /// @dev Indicates that the user already has a pending action
    error UsdnProtocolPendingAction();

    /// @dev Indicates that the user has no pending action
    error UsdnProtocolNoPendingAction();

    /// @dev Indicates that the user has a pending action but its action type is not the expected one
    error UsdnProtocolInvalidPendingAction();

    /// @dev Indicates that the total supply of USDN would fall too low after a withdrawal
    error UsdnProtocolMinTotalSupply();
}

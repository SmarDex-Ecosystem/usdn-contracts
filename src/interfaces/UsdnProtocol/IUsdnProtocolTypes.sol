// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

/**
 * @notice Information about a long user position.
 * @dev 64 bytes packed struct (512 bits)
 * @param leverage The leverage of the position (0 for vault deposits).
 * @param timestamp The timestamp of the position start.
 * @param user The user address.
 * @param amount The amount of the position.
 * @param startPrice The price of the asset at the position opening. TODO: remove once we have the new function to
 * retrieve the value of a position.
 */
struct Position {
    uint40 timestamp; // 5 bytes. Max 1_099_511_627_775 (36812-02-20 01:36:15)
    address user; // 20 bytes
    uint128 leverage; // 16 bytes. Max 340_282_366_920_938_463.463_374_607_431_768_211_455 x
    uint128 amount; // 16 bytes.
    uint128 startPrice; // 16 bytes. Max 340_282_366_920_938_463_463.374_607_431_768_211_455 USD/wstETH
}

/**
 * @notice All possible action types for the protocol.
 * @dev This is used for pending actions and to interact with the oracle middleware.
 * @param None No particular action.
 * @param Initialize The contract is being initialized.
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
    Initialize,
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
 * @notice A pending action in the queue.
 * @param action The action type (Validate...).
 * @param timestamp The timestamp of the initiate action.
 * @param user The user address.
 * @param to The to address.
 * @param var1 See `VaultPendingAction` and `LongPendingAction`.
 * @param amount The amount of the pending action.
 * @param var2 See `VaultPendingAction` and `LongPendingAction`.
 * @param var3 See `VaultPendingAction` and `LongPendingAction`.
 * @param var4 See `VaultPendingAction` and `LongPendingAction`.
 * @param var5 See `VaultPendingAction` and `LongPendingAction`.
 * @param var6 See `VaultPendingAction` and `LongPendingAction`.
 */
struct PendingAction {
    ProtocolAction action; // 1 byte
    uint40 timestamp; // 5 bytes
    address user; // 20 bytes
    address to; // 20 bytes
    int24 var1; // 3 bytes
    uint128 amount; // 16 bytes
    uint128 var2; // 16 bytes
    uint256 var3; // 32 bytes
    uint256 var4; // 32 bytes
    uint256 var5; // 32 bytes
    uint256 var6; // 32 bytes
}

/**
 * @notice A pending action in the queue for a vault deposit or withdrawal.
 * @param action The action type (`ValidateDeposit` or `ValidateWithdrawal`).
 * @param timestamp The timestamp of the initiate action.
 * @param user The user address.
 * @param to The to address.
 * @param _unused Unused field to align the struct to `PendingAction`.
 * @param amount The amount of the pending action.
 * @param assetPrice The price of the asset at the time of last update.
 * @param totalExpo The total exposure at the time of last update.
 * @param balanceVault The balance of the vault at the time of last update.
 * @param balanceLong The balance of the long position at the time of last update.
 * @param usdnTotalSupply The total supply of USDN at the time of the action.
 */
struct VaultPendingAction {
    ProtocolAction action; // 1 byte
    uint40 timestamp; // 5 bytes
    address user; // 20 bytes
    address to; // 20 bytes
    int24 _unused; // 3 bytes
    uint128 amount; // 16 bytes
    uint128 assetPrice; // 16 bytes
    uint256 totalExpo; // 32 bytes
    uint256 balanceVault; // 32 bytes
    uint256 balanceLong; // 32 bytes
    uint256 usdnTotalSupply; // 32 bytes
}

/**
 * @notice A pending action in the queue for a long position.
 * @param action The action type (`ValidateOpenPosition` or `ValidateClosePosition`).
 * @param timestamp The timestamp of the initiate action.
 * @param user The user address.
 * @param to The to address.
 * @param tick The tick of the position.
 * @param closeAmount The amount of the pending action (only used when closing a position).
 * @param closeLeverage The initial leverage of the position (only used when closing a position).
 * @param tickVersion The version of the tick.
 * @param index The index of the position in the tick list.
 * @param closeLiqMultiplier The liquidation multiplier at the time of the last update (only used when closing a
 * position).
 * @param closeTempTransfer The amount that was optimistically removed on `initiateClosePosition` (only used when
 * closing a position).
 */
struct LongPendingAction {
    ProtocolAction action; // 1 byte
    uint40 timestamp; // 5 bytes
    address user; // 20 bytes
    address to; // 20 bytes
    int24 tick; // 3 bytes
    uint128 closeAmount; // 16 bytes
    uint128 closeLeverage; // 16 bytes
    uint256 tickVersion; // 32 bytes
    uint256 index; // 32 bytes
    uint256 closeLiqMultiplier; // 32 bytes
    uint256 closeTempTransfer; // 32 bytes
}

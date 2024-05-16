// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

/**
 * @notice Information about a long user position.
 * @param timestamp The timestamp of the position start.
 * @param user The user address.
 * @param totalExpo The total expo of the position (0 for vault deposits).
 * @param amount The amount of the position.
 */
struct Position {
    uint40 timestamp; // 5 bytes. Max 1_099_511_627_775 (36812-02-20 01:36:15)
    address user; // 20 bytes
    uint128 totalExpo; // 16 bytes. Max 340_282_366_920_938_463_463.374_607_431_768_211_455 ether
    uint128 amount; // 16 bytes.
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
 * @param to The to address.
 * @param validator The validator address.
 * @param securityDepositValue The security deposit of the pending action.
 * @param var1 See `DepositPendingAction`, `WithdrawalPendingAction` and `LongPendingAction`.
 * @param var2 See `DepositPendingAction`, `WithdrawalPendingAction` and `LongPendingAction`.
 * @param var3 See `DepositPendingAction`, `WithdrawalPendingAction` and `LongPendingAction`.
 * @param var4 See `DepositPendingAction`, `WithdrawalPendingAction` and `LongPendingAction`.
 * @param var5 See `DepositPendingAction`, `WithdrawalPendingAction` and `LongPendingAction`.
 * @param var6 See `DepositPendingAction`, `WithdrawalPendingAction` and `LongPendingAction`.
 * @param var7 See `DepositPendingAction`, `WithdrawalPendingAction` and `LongPendingAction`.
 */
struct PendingAction {
    ProtocolAction action; // 1 byte
    uint40 timestamp; // 5 bytes
    address to; // 20 bytes
    address validator; // 20 bytes
    uint64 securityDepositValue; // 8 bytes
    int24 var1; // 3 bytes
    uint128 var2; // 16 bytes
    uint128 var3; // 16 bytes
    uint256 var4; // 32 bytes
    uint256 var5; // 32 bytes
    uint256 var6; // 32 bytes
    uint256 var7; // 32 bytes
}

/**
 * @notice A pending action in the queue for a vault deposit.
 * @param action The action type (Validate...).
 * @param timestamp The timestamp of the initiate action.
 * @param to The to address.
 * @param validator The validator address.
 * @param securityDepositValue The security deposit of the pending action.
 * @param _unused Unused field to align the struct to `PendingAction`.
 * @param amount The amount of assets of the pending deposit.
 * @param assetPrice The price of the asset at the time of the last update.
 * @param totalExpo The total exposure at the time of the last update.
 * @param balanceVault The balance of the vault at the time of the last update.
 * @param balanceLong The balance of the long position at the time of the last update.
 * @param usdnTotalSupply The total supply of USDN at the time of the action.
 */
struct DepositPendingAction {
    ProtocolAction action; // 1 byte
    uint40 timestamp; // 5 bytes
    address to; // 20 bytes
    address validator; // 20 bytes
    uint64 securityDepositValue; // 8 bytes
    int24 _unused; // 3 bytes
    uint128 amount; // 16 bytes
    uint128 assetPrice; // 16 bytes
    uint256 totalExpo; // 32 bytes
    uint256 balanceVault; // 32 bytes
    uint256 balanceLong; // 32 bytes
    uint256 usdnTotalSupply; // 32 bytes
}

/**
 * @notice A pending action in the queue for a vault withdrawal.
 * @param action The action type (Validate...).
 * @param timestamp The timestamp of the initiate action.
 * @param to The to address.
 * @param validator The validator address.
 * @param securityDepositValue The security deposit of the pending action.
 * @param sharesLSB 3 least significant bytes of the withdrawal shares amount (uint152).
 * @param sharesMSB 16 most significant bytes of the withdrawal shares amount (uint152).
 * @param assetPrice The price of the asset at the time of the last update.
 * @param totalExpo The total exposure at the time of the last update.
 * @param balanceVault The balance of the vault at the time of the last update.
 * @param balanceLong The balance of the long position at the time of the last update.
 * @param usdnTotalShares The total shares supply of USDN at the time of the action.
 */
struct WithdrawalPendingAction {
    ProtocolAction action; // 1 byte
    uint40 timestamp; // 5 bytes
    address to; // 20 bytes
    address validator; // 20 bytes
    uint64 securityDepositValue; // 8 bytes
    uint24 sharesLSB; // 3 bytes
    uint128 sharesMSB; // 16 bytes
    uint128 assetPrice; // 16 bytes
    uint256 totalExpo; // 32 bytes
    uint256 balanceVault; // 32 bytes
    uint256 balanceLong; // 32 bytes
    uint256 usdnTotalShares; // 32 bytes
}

/**
 * @notice A pending action in the queue for a long position.
 * @param action The action type (Validate...).
 * @param timestamp The timestamp of the initiate action.
 * @param to The to address.
 * @param validator The validator address.
 * @param securityDepositValue The security deposit of the pending action.
 * @param tick The tick of the position.
 * @param closeAmount The amount of the pending action (only used when closing a position).
 * @param closePosTotalExpo The total expo of the position (only used when closing a position).
 * @param tickVersion The version of the tick.
 * @param index The index of the position in the tick list.
 * @param closeLiqMultiplier A fixed precision representation of the liquidation multiplier (with
 * LIQUIDATION_MULTIPLIER_DECIMALS decimals) used to calculate the effective price for a given tick number (only used
 * when closing a position).
 * @param closeBoundedPositionValue The amount that was removed from the long balance on `initiateClosePosition` (only
 * used when closing a position).
 */
struct LongPendingAction {
    ProtocolAction action; // 1 byte
    uint40 timestamp; // 5 bytes
    address to; // 20 bytes
    address validator; // 20 bytes
    uint64 securityDepositValue; // 8 bytes
    int24 tick; // 3 bytes
    uint128 closeAmount; // 16 bytes
    uint128 closePosTotalExpo; // 16 bytes
    uint256 tickVersion; // 32 bytes
    uint256 index; // 32 bytes
    uint256 closeLiqMultiplier; // 32 bytes
    uint256 closeBoundedPositionValue; // 32 bytes
}

/**
 * @notice The data allowing to validate an actionable pending action.
 * @param priceData An array of bytes, each representing the data to be forwarded to the oracle middleware to validate
 * a pending action in the queue.
 * @param rawIndices An array of raw indices in the pending actions queue, in the same order as the corresponding
 * priceData
 */
struct PreviousActionsData {
    bytes[] priceData;
    uint128[] rawIndices;
}

/**
 * @notice The effects of executed liquidations on the protocol
 * @param liquidatedPositions The number of liquidated positions
 * @param liquidatedTicks The number of liquidated ticks
 * @param remainingCollateral The collateral remaining after the liquidations
 * @param newLongBalance The new balance of the long side
 * @param newVaultBalance The new balance of the vault side
 */
struct LiquidationsEffects {
    uint256 liquidatedPositions;
    uint16 liquidatedTicks;
    int256 remainingCollateral;
    uint256 newLongBalance;
    uint256 newVaultBalance;
}

/**
 * @notice Accumulator for tick data
 * @param totalExpo The sum of the total expo of each position in the tick
 * @param totalPos The number of positions in the tick
 * @param liquidationPenalty The liquidation penalty for the positions in the tick
 * @dev Since the liquidation penalty is a parameter that can be updated, we need to ensure that positions that get
 * created with a given penalty, use this penalty throughout their lifecycle. As such, once a tick gets populated by
 * a first position, it gets assigned the current liquidation penalty parameter value and can't use another value until
 * it gets liquidated.
 */
struct TickData {
    uint256 totalExpo;
    uint248 totalPos;
    uint8 liquidationPenalty;
}

/**
 * @notice The unique identifier for a long position.
 * @param tick The tick of the position.
 * @param tickVersion The version of the tick.
 * @param index The index of the position in the tick list.
 */
struct PositionId {
    int24 tick;
    uint256 tickVersion;
    uint256 index;
}

// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import { Permit2TokenBitfield } from "../../libraries/Permit2TokenBitfield.sol";
import { HugeUint } from "../../libraries/HugeUint.sol";

/**
 * @notice Information about a long user position
 * @param validated Whether the position was validated
 * @param timestamp The timestamp of the position start
 * @param user The user's address
 * @param totalExpo The total expo of the position (0 for vault deposits)
 * @param amount The amount of the position
 */
struct Position {
    bool validated; // 1 byte
    uint40 timestamp; // 5 bytes. Max 1_099_511_627_775 (36812-02-20 01:36:15)
    address user; // 20 bytes
    uint128 totalExpo; // 16 bytes. Max 340_282_366_920_938_463_463.374_607_431_768_211_455 ether
    uint128 amount; // 16 bytes
}

/**
 * @notice All possible action types for the protocol
 * @dev This is used for pending actions and to interact with the oracle middleware
 * @param None No particular action
 * @param Initialize The contract is being initialized
 * @param InitiateDeposit Initiating a `deposit` action
 * @param ValidateDeposit Validating a `deposit` action
 * @param InitiateWithdrawal Initiating a `withdraw` action
 * @param ValidateWithdrawal Validating a `withdraw` action
 * @param InitiateOpenPosition Initiating an `open` position action
 * @param ValidateOpenPosition Validating an `open` position action
 * @param InitiateClosePosition Initiating a `close` position action
 * @param ValidateClosePosition Validating a `close` position action
 * @param Liquidation The price is requested for a liquidation action
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
 * @notice A pending action in the queue
 * @param action The action type
 * @param timestamp The timestamp of the initiate action
 * @param to The `to` address
 * @param validator The `validator` address
 * @param securityDepositValue The security deposit of the pending action
 * @param var1 See `DepositPendingAction`, `WithdrawalPendingAction` and `LongPendingAction`
 * @param var2 See `DepositPendingAction`, `WithdrawalPendingAction` and `LongPendingAction`
 * @param var3 See `DepositPendingAction`, `WithdrawalPendingAction` and `LongPendingAction`
 * @param var4 See `DepositPendingAction`, `WithdrawalPendingAction` and `LongPendingAction`
 * @param var5 See `DepositPendingAction`, `WithdrawalPendingAction` and `LongPendingAction`
 * @param var6 See `DepositPendingAction`, `WithdrawalPendingAction` and `LongPendingAction`
 * @param var7 See `DepositPendingAction`, `WithdrawalPendingAction` and `LongPendingAction`
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
 * @notice A pending action in the queue for a vault deposit
 * @param action The action type
 * @param timestamp The timestamp of the initiate action
 * @param to The `to` address
 * @param validator The `validator` address
 * @param securityDepositValue The security deposit of the pending action
 * @param _unused Unused field to align the struct to `PendingAction`
 * @param amount The amount of assets of the pending deposit
 * @param assetPrice The price of the asset at the time of the last update
 * @param totalExpo The total exposure at the time of the last update
 * @param balanceVault The balance of the vault at the time of the last update
 * @param balanceLong The balance of the long position at the time of the last update
 * @param usdnTotalShares The total supply of USDN shares at the time of the action
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
    uint256 usdnTotalShares; // 32 bytes
}

/**
 * @notice A pending action in the queue for a vault withdrawal
 * @param action The action type
 * @param timestamp The timestamp of the initiate action
 * @param to The `to` address
 * @param validator The `validator` address
 * @param securityDepositValue The security deposit of the pending action
 * @param sharesLSB 3 least significant bytes of the withdrawal shares amount (uint152)
 * @param sharesMSB 16 most significant bytes of the withdrawal shares amount (uint152)
 * @param assetPrice The price of the asset at the time of the last update
 * @param totalExpo The total exposure at the time of the last update
 * @param balanceVault The balance of the vault at the time of the last update
 * @param balanceLong The balance of the long position at the time of the last update
 * @param usdnTotalShares The total shares supply of USDN at the time of the action
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
 * @notice A pending action in the queue for a long position
 * @param action The action type
 * @param timestamp The timestamp of the initiate action
 * @param to The `to` address
 * @param validator The `validator` address
 * @param securityDepositValue The security deposit of the pending action
 * @param tick The tick of the position
 * @param closeAmount The amount of the pending action (only used when closing a position)
 * @param closePosTotalExpo The total expo of the position (only used when closing a position)
 * @param tickVersion The version of the tick
 * @param index The index of the position in the tick list
 * @param closeLiqMultiplier A fixed precision representation of the liquidation multiplier (with
 * `LIQUIDATION_MULTIPLIER_DECIMALS` decimals) used to calculate the effective price for a given tick number (only used
 * when closing a position)
 * @param closeBoundedPositionValue The amount that was removed from the long balance on `initiateClosePosition` (only
 * used when closing a position)
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
 * @notice The data allowing to validate an actionable pending action
 * @param priceData An array of bytes, each representing the data to be forwarded to the oracle middleware to validate
 * a pending action in the queue
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
 * @param isLiquidationPending Whether some ticks are still populated above the current price (left to liquidate)
 */
struct LiquidationsEffects {
    uint256 liquidatedPositions;
    uint16 liquidatedTicks;
    int256 remainingCollateral;
    uint256 newLongBalance;
    uint256 newVaultBalance;
    bool isLiquidationPending;
}

/**
 * @notice Accumulator for tick data
 * @param totalExpo The sum of the total expo of each position in the tick
 * @param totalPos The number of positions in the tick
 * @param liquidationPenalty The liquidation penalty for the positions in the tick
 * @dev Since the liquidation penalty is a parameter that can be updated, we need to ensure that positions that get
 * created with a given penalty, use this penalty throughout their lifecycle. As such, once a tick gets populated by
 * a first position, it gets assigned the current liquidation penalty parameter value and can't use another value until
 * it gets liquidated
 */
struct TickData {
    uint256 totalExpo;
    uint248 totalPos;
    uint8 liquidationPenalty;
}

/**
 * @notice The unique identifier for a long position
 * @param tick The tick of the position
 * @param tickVersion The version of the tick
 * @param index The index of the position in the tick list
 */
struct PositionId {
    int24 tick;
    uint256 tickVersion;
    uint256 index;
}

/**
 * @notice Parameters for the internal `_initiateOpenPosition` function
 * @param user The address of the user initiating the open position
 * @param to The address that will be the owner of the position
 * @param validator The address that will validate the open position
 * @param amount The amount of wstETH to deposit
 * @param desiredLiqPrice The desired liquidation price, including the liquidation penalty
 * @param securityDepositValue The value of the security deposit for the newly created pending action
 * @param permit2TokenBitfield The permit2 bitfield
 * @param currentPriceData The current price data (used to calculate the temporary leverage and entry price,
 * pending validation)
 */
struct InitiateOpenPositionParams {
    address user;
    address to;
    address validator;
    uint128 amount;
    uint128 desiredLiqPrice;
    uint64 securityDepositValue;
    Permit2TokenBitfield.Bitfield permit2TokenBitfield;
}

struct InitiateClosePositionParams {
    PositionId posId;
    uint128 amountToClose;
    address to;
    address payable validator;
}

/**
 * @dev Structure to hold the transient data during `_initiateDeposit`
 * @param pendingActionPrice The adjusted price with position fees applied
 * @param isLiquidationPending Whether some liquidations still need to be performed
 * @param totalExpo The total expo of the long side
 * @param balanceLong The long side balance
 * @param balanceVault The vault side balance, calculated according to the pendingActionPrice
 * @param usdnTotalShares Total minted shares of USDN
 * @param sdexToBurn The amount of SDEX to burn for the deposit
 */
struct InitiateDepositData {
    uint128 pendingActionPrice;
    bool isLiquidationPending;
    uint256 totalExpo;
    uint256 balanceLong;
    uint256 balanceVault;
    uint256 usdnTotalShares;
    uint256 sdexToBurn;
}

/**
 * @dev Structure to hold the transient data during `_initiateWithdrawal`
 * @param pendingActionPrice The adjusted price with position fees applied
 * @param usdnTotalShares The total shares supply of USDN
 * @param totalExpo The current total expo
 * @param balanceLong The current long balance
 * @param balanceVault The vault balance, adjusted according to the pendingActionPrice
 * @param withdrawalAmount The predicted amount of assets that will be withdrawn
 * @param isLiquidationPending Whether some ticks are still populated above the current price (left to liquidate)
 */
struct WithdrawalData {
    uint128 pendingActionPrice;
    uint256 usdnTotalShares;
    uint256 totalExpo;
    uint256 balanceLong;
    uint256 balanceVault;
    uint256 withdrawalAmount;
    bool isLiquidationPending;
}

/**
 * @dev Structure to hold the transient data during `_initiateClosePosition`
 * @param pos The position to close
 * @param liquidationPenalty The liquidation penalty
 * @param totalExpoToClose The total expo to close
 * @param lastPrice The price after the last balances update
 * @param tempPositionValue The bounded value of the position that was removed from the long balance
 * @param longTradingExpo The long trading expo
 * @param liqMulAcc The liquidation multiplier accumulator
 * @param isLiquidationPending Whether some ticks are still populated above the current price (left to liquidate)
 */
struct ClosePositionData {
    Position pos;
    uint8 liquidationPenalty;
    uint128 totalExpoToClose;
    uint128 lastPrice;
    uint256 tempPositionValue;
    uint256 longTradingExpo;
    HugeUint.Uint512 liqMulAcc;
    bool isLiquidationPending;
}

/**
 * @dev Structure to hold the transient data during `_validateOpenPosition`
 * @param action The long pending action
 * @param startPrice The new entry price of the position
 * @param tickHash The tick hash
 * @param pos The position object
 * @param liqPriceWithoutPenalty The new liquidation price without penalty
 * @param leverage The new leverage
 * @param liquidationPenalty The liquidation penalty for the position's tick
 * @param isLiquidationPending Whether some ticks are still populated above the current price (left to liquidate)
 */
struct ValidateOpenPositionData {
    LongPendingAction action;
    uint128 startPrice;
    bytes32 tickHash;
    Position pos;
    uint128 liqPriceWithoutPenalty;
    uint128 leverage;
    uint8 liquidationPenalty;
    bool isLiquidationPending;
}

/**
 * @dev Structure to hold the transient data during `_initiateOpenPosition`
 * @param adjustedPrice The adjusted price with position fees applied
 * @param posId The new position id
 * @param liquidationPenalty The liquidation penalty
 * @param positionTotalExpo The total expo of the position
 * @param isLiquidationPending Whether some ticks are still populated above the current price (left to liquidate)
 */
struct InitiateOpenPositionData {
    uint128 adjustedPrice;
    PositionId posId;
    uint8 liquidationPenalty;
    uint128 positionTotalExpo;
    bool isLiquidationPending;
}

/**
 * @notice Structure to hold the temporary data during liquidation
 * @param tempLongBalance The temporary long balance
 * @param tempVaultBalance The temporary vault balance
 * @param currentTick The current tick (tick corresponding to the current asset price)
 * @param iTick Tick iterator index
 * @param totalExpoToRemove The total expo to remove due to the liquidation of some ticks
 * @param accumulatorValueToRemove The value to remove from the liquidation multiplier accumulator, due to the
 * liquidation of some ticks
 * @param longTradingExpo The long trading expo
 * @param currentPrice The current price of the asset
 * @param accumulator The liquidation multiplier accumulator before the liquidation
 * @param isLiquidationPending Whether some ticks are still populated above the current price (left to liquidate)
 */
struct LiquidationData {
    int256 tempLongBalance;
    int256 tempVaultBalance;
    int24 currentTick;
    int24 iTick;
    uint256 totalExpoToRemove;
    uint256 accumulatorValueToRemove;
    uint256 longTradingExpo;
    uint256 currentPrice;
    HugeUint.Uint512 accumulator;
    bool isLiquidationPending;
}

/**
 * @notice Structure to hold the state of the protocol
 * @param totalExpo The long total expo
 * @param tradingExpo The long trading expo
 * @param longBalance The long balance
 * @param vaultBalance The vault balance
 * @param liqMultiplierAccumulator The liquidation multiplier accumulator
 */
struct CachedProtocolState {
    uint256 totalExpo;
    uint256 tradingExpo;
    uint256 longBalance;
    uint256 vaultBalance;
    HugeUint.Uint512 liqMultiplierAccumulator;
}

/**
 * @dev Structure to hold the transient data during `_applyPnlAndFundingAndLiquidate`
 * @param isPriceRecent Whether the price is recent
 * @param tempLongBalance The temporary long balance
 * @param tempVaultBalance The temporary vault balance
 * @param lastPrice The last price
 */
struct ApplyPnlAndFundingAndLiquidateParams {
    bool isPriceRecent;
    int256 tempLongBalance;
    int256 tempVaultBalance;
    uint128 lastPrice;
}

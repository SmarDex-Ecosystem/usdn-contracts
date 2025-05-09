// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { HugeUint } from "@smardex-solidity-libraries-1/HugeUint.sol";
import { LibBitmap } from "solady/src/utils/LibBitmap.sol";

import { DoubleEndedQueue } from "../../libraries/DoubleEndedQueue.sol";
import { IBaseLiquidationRewardsManager } from "../LiquidationRewardsManager/IBaseLiquidationRewardsManager.sol";
import { IBaseOracleMiddleware } from "../OracleMiddleware/IBaseOracleMiddleware.sol";
import { IBaseRebalancer } from "../Rebalancer/IBaseRebalancer.sol";
import { IUsdn } from "../Usdn/IUsdn.sol";

interface IUsdnProtocolTypes {
    /**
     * @notice All possible action types for the protocol.
     * @dev This is used for pending actions and to interact with the oracle middleware.
     * @param None No particular action.
     * @param Initialize The contract is being initialized.
     * @param InitiateDeposit Initiating a `deposit` action.
     * @param ValidateDeposit Validating a `deposit` action.
     * @param InitiateWithdrawal Initiating a `withdraw` action.
     * @param ValidateWithdrawal Validating a `withdraw` action.
     * @param InitiateOpenPosition Initiating an `open` position action.
     * @param ValidateOpenPosition Validating an `open` position action.
     * @param InitiateClosePosition Initiating a `close` position action.
     * @param ValidateClosePosition Validating a `close` position action.
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
     * @notice The outcome of the call targeting a long position.
     * @param Processed The call did what it was supposed to do.
     * An initiate close has been completed / a pending action was validated.
     * @param Liquidated The position has been liquidated by this call.
     * @param PendingLiquidations The call cannot be completed because of pending liquidations.
     * Try calling the {IUsdnProtocolActions.liquidate} function with a fresh price to unblock the situation.
     */
    enum LongActionOutcome {
        Processed,
        Liquidated,
        PendingLiquidations
    }

    /**
     * @notice Classifies how far in its logic the {UsdnProtocolLongLibrary._triggerRebalancer} function made it to.
     * @dev Used to estimate the gas spent by the function call to more accurately calculate liquidation rewards.
     * @param None The rebalancer is not set.
     * @param NoImbalance The protocol imbalance is not reached.
     * @param PendingLiquidation The rebalancer position should be liquidated.
     * @param NoCloseNoOpen The action neither closes nor opens a position.
     * @param Closed The action only closes a position.
     * @param Opened The action only opens a position.
     * @param ClosedOpened The action closes and opens a position.
     */
    enum RebalancerAction {
        None,
        NoImbalance,
        PendingLiquidation,
        NoCloseNoOpen,
        Closed,
        Opened,
        ClosedOpened
    }

    /**
     * @notice Information about a long user position.
     * @param validated Whether the position was validated.
     * @param timestamp The timestamp of the position start.
     * @param user The user's address.
     * @param totalExpo The total exposure of the position (0 for vault deposits). The product of the initial
     * collateral and the initial leverage.
     * @param amount The amount of initial collateral in the position.
     */
    struct Position {
        bool validated; // 1 byte
        uint40 timestamp; // 5 bytes. Max 1_099_511_627_775 (36812-02-20 01:36:15)
        address user; // 20 bytes
        uint128 totalExpo; // 16 bytes. Max 340_282_366_920_938_463_463.374_607_431_768_211_455 ether
        uint128 amount; // 16 bytes
    }

    /**
     * @notice A pending action in the queue.
     * @param action The action type.
     * @param timestamp The timestamp of the initiate action.
     * @param var0 See {DepositPendingAction}, {WithdrawalPendingAction} and {LongPendingAction}.
     * @param to The target of the action.
     * @param validator The address that is supposed to validate the action.
     * @param securityDepositValue The security deposit of the pending action.
     * @param var1 See {DepositPendingAction}, {WithdrawalPendingAction} and {LongPendingAction}.
     * @param var2 See {DepositPendingAction}, {WithdrawalPendingAction} and {LongPendingAction}.
     * @param var3 See {DepositPendingAction}, {WithdrawalPendingAction} and {LongPendingAction}.
     * @param var4 See {DepositPendingAction}, {WithdrawalPendingAction} and {LongPendingAction}.
     * @param var5 See {DepositPendingAction}, {WithdrawalPendingAction} and {LongPendingAction}.
     * @param var6 See {DepositPendingAction}, {WithdrawalPendingAction} and {LongPendingAction}.
     * @param var7 See {DepositPendingAction}, {WithdrawalPendingAction} and {LongPendingAction}.
     */
    struct PendingAction {
        ProtocolAction action; // 1 byte
        uint40 timestamp; // 5 bytes
        uint24 var0; // 3 bytes
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
     * @param action The action type.
     * @param timestamp The timestamp of the initiate action.
     * @param feeBps Fee for the deposit, in BPS.
     * @param to The recipient of the funds.
     * @param validator The address that is supposed to validate the action.
     * @param securityDepositValue The security deposit of the pending action.
     * @param _unused Unused field to align the struct to `PendingAction`.
     * @param amount The amount of assets of the pending deposit.
     * @param assetPrice The price of the asset at the time of the last update.
     * @param totalExpo The total exposure at the time of the last update.
     * @param balanceVault The balance of the vault at the time of the last update.
     * @param balanceLong The balance of the long position at the time of the last update.
     * @param usdnTotalShares The total supply of USDN shares at the time of the action.
     */
    struct DepositPendingAction {
        ProtocolAction action; // 1 byte
        uint40 timestamp; // 5 bytes
        uint24 feeBps; // 3 bytes
        address to; // 20 bytes
        address validator; // 20 bytes
        uint64 securityDepositValue; // 8 bytes
        uint24 _unused; // 3 bytes
        uint128 amount; // 16 bytes
        uint128 assetPrice; // 16 bytes
        uint256 totalExpo; // 32 bytes
        uint256 balanceVault; // 32 bytes
        uint256 balanceLong; // 32 bytes
        uint256 usdnTotalShares; // 32 bytes
    }

    /**
     * @notice A pending action in the queue for a vault withdrawal.
     * @param action The action type.
     * @param timestamp The timestamp of the initiate action.
     * @param feeBps Fee for the withdrawal, in BPS.
     * @param to The recipient of the funds.
     * @param validator The address that is supposed to validate the action.
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
        uint24 feeBps; // 3 bytes
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
     * @param action The action type.
     * @param timestamp The timestamp of the initiate action.
     * @param closeLiqPenalty The liquidation penalty of the tick (only used when closing a position).
     * @param to The recipient of the position.
     * @param validator The address that is supposed to validate the action.
     * @param securityDepositValue The security deposit of the pending action.
     * @param tick The tick of the position.
     * @param closeAmount The portion of the initial position amount to close (only used when closing a position).
     * @param closePosTotalExpo The total expo of the position (only used when closing a position).
     * @param tickVersion The version of the tick.
     * @param index The index of the position in the tick list.
     * @param liqMultiplier A fixed precision representation of the liquidation multiplier (with
     * `LIQUIDATION_MULTIPLIER_DECIMALS` decimals) used to calculate the effective price for a given tick number.
     * @param closeBoundedPositionValue The amount that was removed from the long balance on
     * {IUsdnProtocolActions.initiateClosePosition} (only used when closing a position).
     */
    struct LongPendingAction {
        ProtocolAction action; // 1 byte
        uint40 timestamp; // 5 bytes
        uint24 closeLiqPenalty; // 3 bytes
        address to; // 20 bytes
        address validator; // 20 bytes
        uint64 securityDepositValue; // 8 bytes
        int24 tick; // 3 bytes
        uint128 closeAmount; // 16 bytes
        uint128 closePosTotalExpo; // 16 bytes
        uint256 tickVersion; // 32 bytes
        uint256 index; // 32 bytes
        uint256 liqMultiplier; // 32 bytes
        uint256 closeBoundedPositionValue; // 32 bytes
    }

    /**
     * @notice The data allowing to validate an actionable pending action.
     * @param priceData An array of bytes, each representing the data to be forwarded to the oracle middleware to
     * validate a pending action in the queue.
     * @param rawIndices An array of raw indices in the pending actions queue, in the same order as the corresponding
     * priceData.
     */
    struct PreviousActionsData {
        bytes[] priceData;
        uint128[] rawIndices;
    }

    /**
     * @notice Information of a liquidated tick.
     * @param totalPositions The total number of positions in the tick.
     * @param totalExpo The total expo of the tick.
     * @param remainingCollateral The remaining collateral after liquidation.
     * @param tickPrice The corresponding price.
     * @param priceWithoutPenalty The price without the liquidation penalty.
     */
    struct LiqTickInfo {
        uint256 totalPositions;
        uint256 totalExpo;
        int256 remainingCollateral;
        uint128 tickPrice;
        uint128 priceWithoutPenalty;
    }

    /**
     * @notice The effects of executed liquidations on the protocol.
     * @param liquidatedPositions The total number of liquidated positions.
     * @param remainingCollateral The remaining collateral after liquidation.
     * @param newLongBalance The new balance of the long side.
     * @param newVaultBalance The new balance of the vault side.
     * @param isLiquidationPending Whether some ticks are still populated above the current price (left to liquidate).
     * @param liquidatedTicks Information about the liquidated ticks.
     */
    struct LiquidationsEffects {
        uint256 liquidatedPositions;
        int256 remainingCollateral;
        uint256 newLongBalance;
        uint256 newVaultBalance;
        bool isLiquidationPending;
        LiqTickInfo[] liquidatedTicks;
    }

    /**
     * @notice Accumulator for tick data.
     * @param totalExpo The sum of the total expo of each position in the tick.
     * @param totalPos The number of positions in the tick.
     * @param liquidationPenalty The liquidation penalty for the positions in the tick.
     * @dev Since the liquidation penalty is a parameter that can be updated, we need to ensure that positions that get
     * created with a given penalty, use this penalty throughout their lifecycle. As such, once a tick gets populated by
     * a first position, it gets assigned the current liquidation penalty parameter value and can't use another value
     * until it gets liquidated or all positions exit the tick.
     */
    struct TickData {
        uint256 totalExpo;
        uint248 totalPos;
        uint24 liquidationPenalty;
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

    /**
     * @notice Parameters for the internal {UsdnProtocolActionsLongLibrary._initiateOpenPosition} function.
     * @param user The address of the user initiating the open position.
     * @param to The address that will be the owner of the position.
     * @param validator The address that is supposed to validate the action.
     * @param amount The amount of assets to deposit.
     * @param desiredLiqPrice The desired liquidation price, including the liquidation penalty.
     * @param userMaxPrice The maximum price at which the position can be opened. The userMaxPrice is compared with the
     * price after confidence interval, penalty, etc...
     * @param userMaxLeverage The maximum leverage for the newly created position.
     * @param deadline The deadline of the open position to be initiated.
     * @param securityDepositValue The value of the security deposit for the newly created pending action.
     * @param currentPriceData The current price data (used to calculate the temporary leverage and entry price,
     * pending validation).
     */
    struct InitiateOpenPositionParams {
        address user;
        address to;
        address validator;
        uint128 amount;
        uint128 desiredLiqPrice;
        uint128 userMaxPrice;
        uint256 userMaxLeverage;
        uint256 deadline;
        uint64 securityDepositValue;
    }

    /**
     * @notice Parameters for the internal {UsdnProtocolLongLibrary._prepareInitiateOpenPosition} function.
     * @param validator The address that is supposed to validate the action.
     * @param amount The amount of assets to deposit.
     * @param desiredLiqPrice The desired liquidation price, including the liquidation penalty.
     * @param userMaxPrice The maximum price at which the position can be opened. The userMaxPrice is compared with the
     * price after confidence interval, penalty, etc...
     * @param userMaxLeverage The maximum leverage for the newly created position.
     * @param currentPriceData The current price data.
     */
    struct PrepareInitiateOpenPositionParams {
        address validator;
        uint128 amount;
        uint128 desiredLiqPrice;
        uint256 userMaxPrice;
        uint256 userMaxLeverage;
        bytes currentPriceData;
    }

    /**
     * @notice Parameters for the internal {UsdnProtocolActionsUtilsLibrary._prepareClosePositionData} function.
     * @param to The recipient of the funds.
     * @param validator The address that is supposed to validate the action.
     * @param posId The unique identifier of the position.
     * @param amountToClose The amount of collateral to remove from the position's amount.
     * @param userMinPrice The minimum price at which the position can be closed.
     * @param deadline The deadline until the position can be closed.
     * @param currentPriceData The current price data.
     * @param delegationSignature An EIP712 signature that proves the caller is authorized by the owner of the position
     * to close it on their behalf.
     * @param domainSeparatorV4 The domain separator v4.
     */
    struct PrepareInitiateClosePositionParams {
        address to;
        address validator;
        PositionId posId;
        uint128 amountToClose;
        uint256 userMinPrice;
        uint256 deadline;
        bytes currentPriceData;
        bytes delegationSignature;
        bytes32 domainSeparatorV4;
    }

    /**
     * @notice Parameters for the internal {UsdnProtocolActionsLongLibrary._initiateClosePosition} function.
     * @param to The recipient of the funds.
     * @param validator The address that is supposed to validate the action.
     * @param posId The unique identifier of the position.
     * @param amountToClose The amount to close.
     * @param userMinPrice The minimum price at which the position can be closed.
     * @param deadline The deadline of the close position to be initiated.
     * @param securityDepositValue The value of the security deposit for the newly created pending action.
     * @param domainSeparatorV4 The domain separator v4 for EIP712 signature.
     */
    struct InitiateClosePositionParams {
        address to;
        address payable validator;
        uint256 deadline;
        PositionId posId;
        uint128 amountToClose;
        uint256 userMinPrice;
        uint64 securityDepositValue;
        bytes32 domainSeparatorV4;
    }

    /**
     * @dev Structure to hold the transient data during {UsdnProtocolActionsLongLibrary._initiateClosePosition}
     * @param pos The position to close.
     * @param liquidationPenalty The liquidation penalty.
     * @param totalExpoToClose The total expo to close.
     * @param lastPrice The price after the last balances update.
     * @param tempPositionValue The bounded value of the position that was removed from the long balance.
     * @param longTradingExpo The long trading expo.
     * @param liqMulAcc The liquidation multiplier accumulator.
     * @param isLiquidationPending Whether some ticks are still populated above the current price (left to liquidate).
     */
    struct ClosePositionData {
        Position pos;
        uint24 liquidationPenalty;
        uint128 totalExpoToClose;
        uint128 lastPrice;
        uint256 tempPositionValue;
        uint256 longTradingExpo;
        HugeUint.Uint512 liqMulAcc;
        bool isLiquidationPending;
    }

    /**
     * @dev Structure to hold the transient data during {UsdnProtocolActionsLongLibrary._validateOpenPosition}.
     * @param action The long pending action.
     * @param startPrice The new entry price of the position.
     * @param lastPrice The price of the last balances update.
     * @param tickHash The tick hash.
     * @param pos The position object.
     * @param liqPriceWithoutPenaltyNorFunding The liquidation price without penalty nor funding used to calculate the
     * user leverage and the new total expo.
     * @param liqPriceWithoutPenalty The new liquidation price without penalty.
     * @param leverage The new leverage.
     * @param oldPosValue The value of the position according to the old entry price and the _lastPrice.
     * @param liquidationPenalty The liquidation penalty for the position's tick.
     * @param isLiquidationPending Whether some ticks are still populated above the current price (left to liquidate).
     */
    struct ValidateOpenPositionData {
        LongPendingAction action;
        uint128 startPrice;
        uint128 lastPrice;
        bytes32 tickHash;
        Position pos;
        uint128 liqPriceWithoutPenaltyNorFunding;
        uint128 liqPriceWithoutPenalty;
        uint256 leverage;
        uint256 oldPosValue;
        uint24 liquidationPenalty;
        bool isLiquidationPending;
    }

    /**
     * @dev Structure to hold the transient data during {UsdnProtocolActionsLongLibrary._initiateOpenPosition}.
     * @param adjustedPrice The adjusted price with position fees applied.
     * @param posId The unique identifier of the position.
     * @param liquidationPenalty The liquidation penalty.
     * @param positionTotalExpo The total expo of the position. The product of the initial collateral and the initial
     * leverage.
     * @param positionValue The value of the position, taking into account the position fee.
     * @param liqMultiplier The liquidation multiplier represented with fixed precision.
     * @param isLiquidationPending Whether some ticks are still populated above the current price (left to liquidate).
     */
    struct InitiateOpenPositionData {
        uint128 adjustedPrice;
        PositionId posId;
        uint24 liquidationPenalty;
        uint128 positionTotalExpo;
        uint256 positionValue;
        uint256 liqMultiplier;
        bool isLiquidationPending;
    }

    /**
     * @notice Structure to hold the state of the protocol.
     * @param totalExpo The long total expo.
     * @param tradingExpo The long trading expo.
     * @param longBalance The long balance.
     * @param vaultBalance The vault balance.
     * @param liqMultiplierAccumulator The liquidation multiplier accumulator.
     */
    struct CachedProtocolState {
        uint256 totalExpo;
        uint256 tradingExpo;
        uint256 longBalance;
        uint256 vaultBalance;
        HugeUint.Uint512 liqMultiplierAccumulator;
    }

    /**
     * @notice Structure to hold transient data during the {UsdnProtocolActionsLongLibrary._calcRebalancerPositionTick}
     * function.
     * @param protocolMaxLeverage The protocol maximum leverage.
     * @param longImbalanceTargetBps The long imbalance target in basis points.
     * @param tradingExpoToFill The trading expo to fill.
     * @param highestUsableTradingExpo The highest usable trading expo.
     * @param currentLiqPenalty The current liquidation penalty.
     * @param liqPriceWithoutPenalty The liquidation price without penalty.
     */
    struct CalcRebalancerPositionTickData {
        uint256 protocolMaxLeverage;
        int256 longImbalanceTargetBps;
        uint256 tradingExpoToFill;
        uint256 highestUsableTradingExpo;
        uint24 currentLiqPenalty;
        uint128 liqPriceWithoutPenalty;
    }

    /**
     * @notice Structure to hold the return values of the {UsdnProtocolActionsLongLibrary._calcRebalancerPositionTick}
     * function.
     * @param tick The tick of the rebalancer position, includes liquidation penalty.
     * @param totalExpo The total expo of the rebalancer position.
     * @param liquidationPenalty The liquidation penalty of the tick.
     */
    struct RebalancerPositionData {
        int24 tick;
        uint128 totalExpo;
        uint24 liquidationPenalty;
    }

    /**
     * @notice Data structure for the {UsdnProtocolCoreLibrary._applyPnlAndFunding} function.
     * @param tempLongBalance The new balance of the long side, could be negative (temporarily).
     * @param tempVaultBalance The new balance of the vault side, could be negative (temporarily).
     * @param lastPrice The last price.
     */
    struct ApplyPnlAndFundingData {
        int256 tempLongBalance;
        int256 tempVaultBalance;
        uint128 lastPrice;
    }

    /**
     * @notice Data structure for tick to price conversion functions.
     * @param tradingExpo The long side trading expo.
     * @param accumulator The liquidation multiplier accumulator.
     * @param tickSpacing The tick spacing.
     */
    struct TickPriceConversionData {
        uint256 tradingExpo;
        HugeUint.Uint512 accumulator;
        int24 tickSpacing;
    }

    /**
     * @custom:storage-location erc7201:UsdnProtocol.storage.main.
     * @notice Structure to hold the state of the protocol.
     * @param _tickSpacing The liquidation tick spacing for storing long positions.
     * A tick spacing of 1 is equivalent to a 0.01% increase in liquidation price between ticks. A tick spacing of
     * 100 is equivalent to a ~1.005% increase in liquidation price between ticks.
     * @param _asset The asset ERC20 contract.
     * Assets with a blacklist are not supported because the protocol would be DoS if transfers revert.
     * @param _assetDecimals The number of decimals used by the `_asset`.
     * @param _priceFeedDecimals The price feed decimals (18).
     * @param _usdn The USDN ERC20 contract.
     * @param _sdex The SDEX ERC20 contract.
     * @param _usdnMinDivisor The minimum divisor for USDN.
     * @param _oracleMiddleware The oracle middleware contract.
     * @param _liquidationRewardsManager The liquidation rewards manager contract.
     * @param _rebalancer The rebalancer contract.
     * @param _isRebalancer Whether an address is or has been a rebalancer.
     * @param _minLeverage The minimum leverage for a position.
     * @param _maxLeverage The maximum leverage for a position.
     * @param _lowLatencyValidatorDeadline The deadline for a user to confirm their action with a low-latency oracle.
     * After this deadline, any user can validate the action with the low-latency oracle until the
     * OracleMiddleware's _lowLatencyDelay. This is an offset compared to the timestamp of the initiate action.
     * @param _onChainValidatorDeadline The deadline for a user to confirm their action with an on-chain oracle.
     * After this deadline, any user can validate the action with the on-chain oracle. This is an offset compared
     * to the timestamp of the initiate action + the oracle middleware's _lowLatencyDelay.
     * @param _safetyMarginBps Safety margin for the liquidation price of newly open positions, in basis points.
     * @param _liquidationIteration The number of iterations to perform during the user's action (in tick).
     * @param _protocolFeeBps The protocol fee in basis points.
     * @param _rebalancerBonusBps Part of the remaining collateral that is given as a bonus to the Rebalancer upon
     * liquidation of a tick, in basis points. The rest is sent to the Vault balance.
     * @param _liquidationPenalty The liquidation penalty (in ticks).
     * @param _EMAPeriod The moving average period of the funding rate.
     * @param _fundingSF The scaling factor (SF) of the funding rate.
     * @param _feeThreshold The threshold above which the fee will be sent.
     * @param _openExpoImbalanceLimitBps The imbalance limit of the long expo for open actions (in basis points).
     * As soon as the difference between the vault expo and the long expo exceeds this basis point limit in favor
     * of long the open rebalancing mechanism is triggered, preventing the opening of a new long position.
     * @param _withdrawalExpoImbalanceLimitBps The imbalance limit of the long expo for withdrawal actions (in basis
     * points). As soon as the difference between vault expo and long expo exceeds this basis point limit in favor of
     * long, the withdrawal rebalancing mechanism is triggered, preventing the withdrawal of the existing vault
     * position.
     * @param _depositExpoImbalanceLimitBps The imbalance limit of the vault expo for deposit actions (in basis points).
     * As soon as the difference between the vault expo and the long expo exceeds this basis point limit in favor
     * of the vault, the deposit vault rebalancing mechanism is triggered, preventing the opening of a new vault
     * position.
     * @param _closeExpoImbalanceLimitBps The imbalance limit of the vault expo for close actions (in basis points).
     * As soon as the difference between the vault expo and the long expo exceeds this basis point limit in favor
     * of the vault, the close rebalancing mechanism is triggered, preventing the close of an existing long position.
     * @param _rebalancerCloseExpoImbalanceLimitBps The imbalance limit of the vault expo for close actions from the
     * rebalancer (in basis points). As soon as the difference between the vault expo and the long expo exceeds this
     * basis point limit in favor of the vault, the close rebalancing mechanism is triggered, preventing the close of an
     * existing long position from the rebalancer contract.
     * @param _longImbalanceTargetBps The target imbalance on the long side (in basis points)
     * This value will be used to calculate how much of the missing trading expo the rebalancer position will try
     * to compensate. A negative value means the rebalancer will compensate enough to go above the equilibrium. A
     * positive value means the rebalancer will compensate but stay below the equilibrium.
     * @param _positionFeeBps The position fee in basis points.
     * @param _vaultFeeBps The fee for vault deposits and withdrawals, in basis points.
     * @param _sdexRewardsRatioBps The ratio of SDEX rewards to send to the user (in basis points).
     * @param __unused Old slot for `_sdexBurnOnDepositRatio`.
     * @param _feeCollector The fee collector's address.
     * @param _securityDepositValue The deposit required for a new position.
     * @param _targetUsdnPrice The nominal (target) price of USDN (with _priceFeedDecimals).
     * @param _usdnRebaseThreshold The USDN price threshold to trigger a rebase (with _priceFeedDecimals).
     * @param _minLongPosition The minimum long position size (with `_assetDecimals`).
     * @param _lastFundingPerDay The funding rate calculated at the last update timestamp.
     * @param _lastPrice The price of the asset during the last balances update (with price feed decimals).
     * @param _lastUpdateTimestamp The timestamp of the last balances update.
     * @param _pendingProtocolFee The pending protocol fee accumulator.
     * @param _pendingActions The pending actions by the user (1 per user max).
     * The value stored is an index into the `pendingActionsQueue` deque, shifted by one. A value of 0 means no
     * pending action. Since the deque uses uint128 indices, the highest index will not overflow when adding one.
     * @param _pendingActionsQueue The queue of pending actions.
     * @param _balanceVault The balance of deposits (with `_assetDecimals`).
     * @param _pendingBalanceVault The unreflected balance change due to pending vault actions (with `_assetDecimals`).
     * @param _EMA The exponential moving average of the funding (0.0003 at initialization).
     * @param _balanceLong The balance of long positions (with `_assetDecimals`).
     * @param _totalExpo The total exposure of the long positions (with `_assetDecimals`).
     * @param _liqMultiplierAccumulator The accumulator used to calculate the liquidation multiplier.
     * This is the sum, for all ticks, of the total expo of positions inside the tick, multiplied by the
     * unadjusted price of the tick which is `_tickData[tickHash].liquidationPenalty` below
     * The unadjusted price is obtained with `TickMath.getPriceAtTick.
     * @param _tickVersion The liquidation tick version.
     * @param _longPositions The long positions per versioned tick (liquidation price).
     * @param _tickData Accumulated data for a given tick and tick version.
     * @param _highestPopulatedTick The highest tick with a position.
     * @param _totalLongPositions Cache of the total long positions count.
     * @param _tickBitmap The bitmap used to quickly find populated ticks.
     * @param _protocolFallbackAddr The address of the fallback contract.
     * @param _nonce The user EIP712 nonce.
     * @param _sdexBurnOnDepositRatio The ratio of USDN to SDEX tokens to burn on deposit.
     */
    struct Storage {
        // immutable
        int24 _tickSpacing;
        IERC20Metadata _asset;
        uint8 _assetDecimals;
        uint8 _priceFeedDecimals;
        IUsdn _usdn;
        IERC20Metadata _sdex;
        uint256 _usdnMinDivisor;
        // parameters
        IBaseOracleMiddleware _oracleMiddleware;
        IBaseLiquidationRewardsManager _liquidationRewardsManager;
        IBaseRebalancer _rebalancer;
        mapping(address => bool) _isRebalancer;
        uint256 _minLeverage;
        uint256 _maxLeverage;
        uint128 _lowLatencyValidatorDeadline;
        uint128 _onChainValidatorDeadline;
        uint256 _safetyMarginBps;
        uint16 _liquidationIteration;
        uint16 _protocolFeeBps;
        uint16 _rebalancerBonusBps;
        uint24 _liquidationPenalty;
        uint128 _EMAPeriod;
        uint256 _fundingSF;
        uint256 _feeThreshold;
        int256 _openExpoImbalanceLimitBps;
        int256 _withdrawalExpoImbalanceLimitBps;
        int256 _depositExpoImbalanceLimitBps;
        int256 _closeExpoImbalanceLimitBps;
        int256 _rebalancerCloseExpoImbalanceLimitBps;
        int256 _longImbalanceTargetBps;
        uint16 _positionFeeBps;
        uint16 _vaultFeeBps;
        uint16 _sdexRewardsRatioBps;
        uint32 __unused;
        address _feeCollector;
        uint64 _securityDepositValue;
        uint128 _targetUsdnPrice;
        uint128 _usdnRebaseThreshold;
        uint256 _minLongPosition;
        // state
        int256 _lastFundingPerDay;
        uint128 _lastPrice;
        uint128 _lastUpdateTimestamp;
        uint256 _pendingProtocolFee;
        // pending actions queue
        mapping(address => uint256) _pendingActions;
        DoubleEndedQueue.Deque _pendingActionsQueue;
        // vault
        uint256 _balanceVault;
        int256 _pendingBalanceVault;
        // long positions
        int256 _EMA;
        uint256 _balanceLong;
        uint256 _totalExpo;
        HugeUint.Uint512 _liqMultiplierAccumulator;
        mapping(int24 => uint256) _tickVersion;
        mapping(bytes32 => Position[]) _longPositions;
        mapping(bytes32 => TickData) _tickData;
        int24 _highestPopulatedTick;
        uint256 _totalLongPositions;
        LibBitmap.Bitmap _tickBitmap;
        // fallback
        address _protocolFallbackAddr;
        // EIP712
        mapping(address => uint256) _nonce;
        uint64 _sdexBurnOnDepositRatio;
    }

    /**
     * @notice Structure to hold initial parameters for the protocol.
     * @param tickSpacing The liquidation tick spacing for storing long positions.
     * @param asset The asset ERC20 contract.
     * @param usdn The USDN ERC20 contract.
     * @param sdex The SDEX ERC20 contract.
     * @param oracleMiddleware The oracle middleware contract.
     * @param liquidationRewardsManager The liquidation rewards manager contract.
     * @param minLeverage The minimum leverage for a position.
     * @param maxLeverage The maximum leverage for a position.
     * @param lowLatencyValidatorDeadline The deadline for a user to confirm their action with a low-latency oracle.
     * @param onChainValidatorDeadline The deadline for a user to confirm their action with an on-chain oracle.
     * @param safetyMarginBps Safety margin for the liquidation price of newly open positions, in basis points.
     * @param liquidationIteration The number of iterations to perform during the user's action (in tick).
     * @param protocolFeeBps The protocol fee in basis points.
     * @param rebalancerBonusBps Part of the remaining collateral that is given as a bonus to the Rebalancer upon
     * liquidation of a tick, in basis points. The rest is sent to the Vault balance.
     * @param liquidationPenalty The liquidation penalty (in ticks).
     * @param emaPeriod The moving average period of the funding rate.
     * @param fundingSF The scaling factor (SF) of the funding rate.
     * @param feeThreshold The threshold above which the fee will be sent.
     * @param openExpoImbalanceLimitBps The imbalance limit of the long expo for open actions (in basis points).
     * @param withdrawalExpoImbalanceLimitBps The imbalance limit of the long expo for withdrawal actions (in basis
     * points).
     * @param depositExpoImbalanceLimitBps The imbalance limit of the vault expo for deposit actions (in basis points).
     * @param closeExpoImbalanceLimitBps The imbalance limit of the vault expo for close actions (in basis points).
     * @param rebalancerCloseExpoImbalanceLimitBps The imbalance limit of the vault expo for close actions from the
     * rebalancer (in basis points).
     * @param longImbalanceTargetBps The target imbalance on the long side (in basis points)
     * @param positionFeeBps The position fee in basis points.
     * @param vaultFeeBps The fee for vault deposits and withdrawals, in basis points.
     * @param sdexRewardsRatioBps The ratio of SDEX rewards to send to the user (in basis points).
     * @param sdexBurnOnDepositRatio The ratio of USDN to SDEX tokens to burn on deposit.
     * @param feeCollector The fee collector's address.
     * @param securityDepositValue The deposit required for a new position.
     * @param targetUsdnPrice The nominal (target) price of USDN (with _priceFeedDecimals).
     * @param usdnRebaseThreshold The USDN price threshold to trigger a rebase (with _priceFeedDecimals).
     * @param minLongPosition The minimum long position size (with `_assetDecimals`).
     * @param EMA The exponential moving average of the funding (0.0003 at initialization).
     * @param protocolFallbackAddr The address of the fallback contract.
     */
    struct InitStorage {
        int24 tickSpacing;
        IERC20Metadata asset;
        IUsdn usdn;
        IERC20Metadata sdex;
        IBaseOracleMiddleware oracleMiddleware;
        IBaseLiquidationRewardsManager liquidationRewardsManager;
        uint256 minLeverage;
        uint256 maxLeverage;
        uint128 lowLatencyValidatorDeadline;
        uint128 onChainValidatorDeadline;
        uint256 safetyMarginBps;
        uint16 liquidationIteration;
        uint16 protocolFeeBps;
        uint16 rebalancerBonusBps;
        uint24 liquidationPenalty;
        uint128 emaPeriod;
        uint256 fundingSF;
        uint256 feeThreshold;
        int256 openExpoImbalanceLimitBps;
        int256 withdrawalExpoImbalanceLimitBps;
        int256 depositExpoImbalanceLimitBps;
        int256 closeExpoImbalanceLimitBps;
        int256 rebalancerCloseExpoImbalanceLimitBps;
        int256 longImbalanceTargetBps;
        uint16 positionFeeBps;
        uint16 vaultFeeBps;
        uint16 sdexRewardsRatioBps;
        uint64 sdexBurnOnDepositRatio;
        address feeCollector;
        uint64 securityDepositValue;
        uint128 targetUsdnPrice;
        uint128 usdnRebaseThreshold;
        uint256 minLongPosition;
        int256 EMA;
        address protocolFallbackAddr;
    }
}

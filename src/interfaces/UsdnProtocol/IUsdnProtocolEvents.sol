// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import { IUsdnProtocolTypes } from "./IUsdnProtocolTypes.sol";

/**
 * @title IUsdnProtocolEvents
 * @notice Events for the USDN Protocol
 */
interface IUsdnProtocolEvents is IUsdnProtocolTypes {
    /**
     * @notice Emitted when a user initiates a deposit
     * @param to The address that will receive the USDN tokens
     * @param validator The address of the validator that will validate the deposit
     * @param amount The amount of assets that were deposited
     * @param feeBps The fee in basis points
     * @param timestamp The timestamp of the action
     * @param sdexBurned The amount of SDEX tokens burned
     */
    event InitiatedDeposit(
        address indexed to,
        address indexed validator,
        uint256 amount,
        uint256 feeBps,
        uint256 timestamp,
        uint256 sdexBurned
    );

    /**
     * @notice Emitted when a user validates a deposit
     * @param to The address that received the USDN tokens
     * @param validator The address of the validator that validated the deposit
     * @param amountWithFees The amount of assets that were deposited after fees
     * @param usdnMinted The amount of USDN that was minted
     * @param timestamp The timestamp of the InitiatedDeposit action
     */
    event ValidatedDeposit(
        address indexed to, address indexed validator, uint256 amountWithFees, uint256 usdnMinted, uint256 timestamp
    );

    /**
     * @notice Emitted when a user initiates a withdrawal
     * @param to The address that will receive the assets
     * @param validator The address of the validator that will validate the withdrawal
     * @param usdnAmount The amount of USDN that will be burned
     * @param timestamp The timestamp of the action
     */
    event InitiatedWithdrawal(address indexed to, address indexed validator, uint256 usdnAmount, uint256 timestamp);

    /**
     * @notice Emitted when a user validates a withdrawal
     * @param to The address that received the assets
     * @param validator The address of the validator that validated the withdrawal
     * @param amountWithdrawn The amount of assets that were withdrawn
     * @param usdnBurned The amount of USDN that was burned
     * @param timestamp The timestamp of the InitiatedWithdrawal action
     */
    event ValidatedWithdrawal(
        address indexed to, address indexed validator, uint256 amountWithdrawn, uint256 usdnBurned, uint256 timestamp
    );

    /**
     * @notice Emitted when a user initiates the opening of a long position
     * @param owner The address that owns the position
     * @param validator The address of the validator that will validate the position
     * @param timestamp The timestamp of the action
     * @param totalExpo The initial total expo of the position (pending validation)
     * @param amount The amount of assets that were deposited as collateral
     * @param startPrice The asset price at the moment of the position creation (pending validation)
     * @param posId The unique position identifier
     */
    event InitiatedOpenPosition(
        address indexed owner,
        address indexed validator,
        uint40 timestamp,
        uint128 totalExpo,
        uint128 amount,
        uint128 startPrice,
        PositionId posId
    );

    /**
     * @notice Emitted when a user validates the opening of a long position
     * @param owner The address that owns the position
     * @param validator The address of the validator that validated the position
     * @param totalExpo The total expo of the position
     * @param newStartPrice The asset price at the moment of the position creation (final)
     * @param posId The unique position identifier
     * If changed compared to `InitiatedOpenLong`, then `LiquidationPriceUpdated` will be emitted too
     */
    event ValidatedOpenPosition(
        address indexed owner, address indexed validator, uint128 totalExpo, uint128 newStartPrice, PositionId posId
    );

    /**
     * @notice Emitted when a position was moved from one tick to another
     * @param oldPosId The old position identifier
     * @param newPosId The new position identifier
     */
    event LiquidationPriceUpdated(PositionId indexed oldPosId, PositionId newPosId);

    /**
     * @notice Emitted when a user initiates the closing of all or part of a long position
     * @param owner The owner of this position
     * @param validator The validator for the pending action
     * @param to The address that will receive the assets
     * @param posId The unique position identifier
     * @param originalAmount The amount of collateral originally on the position
     * @param amountToClose The amount of collateral to close from the position
     * If the entirety of the position is being closed, this value equals `originalAmount`
     * @param totalExpoRemaining The total expo remaining in the position
     * If the entirety of the position is being closed, this value is zero
     */
    event InitiatedClosePosition(
        address indexed owner,
        address indexed validator,
        address indexed to,
        PositionId posId,
        uint128 originalAmount,
        uint128 amountToClose,
        uint128 totalExpoRemaining
    );

    /**
     * @notice Emitted when a user validates the closing of a long position
     * @param validator The validator of the close action, not necessarily the position owner
     * @param to The address that received the assets
     * @param posId The unique position identifier
     * @param amountReceived The amount of assets that were sent to the user
     * @param profit The profit that the user made
     */
    event ValidatedClosePosition(
        address indexed validator, address indexed to, PositionId posId, uint256 amountReceived, int256 profit
    );

    /**
     * @notice Emitted when a tick is liquidated
     * @param tick The liquidated tick
     * @param oldTickVersion The liquidated tick version
     * @param liquidationPrice The asset price at the moment of liquidation
     * @param effectiveTickPrice The effective liquidated tick price
     * @param remainingCollateral The amount of asset that was left in the tick, which was transferred to the vault if
     * positive, or was taken from the vault if negative
     */
    event LiquidatedTick(
        int24 indexed tick,
        uint256 indexed oldTickVersion,
        uint256 liquidationPrice,
        uint256 effectiveTickPrice,
        int256 remainingCollateral
    );

    /**
     * @notice Emitted when a position is individually liquidated
     * @param user The validator of the close action, not necessarily the owner of the position
     * @param posId The unique identifier for the position that was liquidated
     * @param liquidationPrice The asset price at the moment of liquidation
     * @param effectiveTickPrice The effective liquidated tick price
     */
    event LiquidatedPosition(
        address indexed user, PositionId posId, uint256 liquidationPrice, uint256 effectiveTickPrice
    );

    /**
     * @notice Emitted when a user's position was liquidated while pending validation and we removed the pending action
     * @param validator The validator address
     * @param posId The unique position identifier
     */
    event StalePendingActionRemoved(address indexed validator, PositionId posId);

    /**
     * @notice Emitted when the position fee is updated
     * @param positionFee The new position fee (in basis points)
     */
    event PositionFeeUpdated(uint256 positionFee);

    /**
     * @notice Emitted when the vault fee is updated
     * @param vaultFee The new vault fee (in basis points)
     */
    event VaultFeeUpdated(uint256 vaultFee);

    /**
     * @notice Emitted when the rebalancer bonus is updated
     * @param bonus The new bonus (in basis points)
     */
    event RebalancerBonusUpdated(uint256 bonus);
    /**
     * @notice Emitted when the ratio of USDN to SDEX tokens to burn on deposit is updated
     * @param newRatio The new ratio
     */
    event BurnSdexOnDepositRatioUpdated(uint256 newRatio);

    /**
     * @notice Emitted when the deposit value is updated
     * @param securityDepositValue The new deposit value
     */
    event SecurityDepositValueUpdated(uint256 securityDepositValue);

    /**
     * @notice Emitted when the oracle middleware is updated
     * @param newMiddleware The new oracle middleware address
     */
    event OracleMiddlewareUpdated(address newMiddleware);

    /**
     * @notice Emitted when the `minLeverage` is updated
     * @param newMinLeverage The new `minLeverage`
     */
    event MinLeverageUpdated(uint256 newMinLeverage);

    /**
     * @notice Emitted when the `maxLeverage` is updated
     * @param newMaxLeverage The new `maxLeverage`
     */
    event MaxLeverageUpdated(uint256 newMaxLeverage);

    /**
     * @notice Emitted when the `validationDeadline` is updated
     * @param newValidationDeadline The new `validationDeadline`
     */
    event ValidationDeadlineUpdated(uint256 newValidationDeadline);

    /**
     * @notice Emitted when the `liquidationPenalty` is updated
     * @param newLiquidationPenalty The new `liquidationPenalty`
     */
    event LiquidationPenaltyUpdated(uint24 newLiquidationPenalty);

    /**
     * @notice Emitted when the `safetyMargin` is updated
     * @param newSafetyMargin The new `safetyMargin`
     */
    event SafetyMarginBpsUpdated(uint256 newSafetyMargin);

    /**
     * @notice Emitted when the `liquidationIteration` is updated
     * @param newLiquidationIteration The new `liquidationIteration`
     */
    event LiquidationIterationUpdated(uint16 newLiquidationIteration);

    /**
     * @notice Emitted when the EMAPeriod is updated
     * @param newEMAPeriod The new EMAPeriod
     */
    event EMAPeriodUpdated(uint128 newEMAPeriod);

    /**
     * @notice Emitted when the `fundingSF` is updated
     * @param newFundingSF The new `fundingSF`
     */
    event FundingSFUpdated(uint256 newFundingSF);

    /**
     * @notice Emitted when a user (liquidator) successfully liquidated positions
     * @param liquidator The address that initiated the liquidation
     * @param rewards The amount of tokens the liquidator received in rewards
     */
    event LiquidatorRewarded(address indexed liquidator, uint256 rewards);

    /**
     * @notice Emitted when the `LiquidationRewardsManager` contract is updated
     * @param newAddress The address of the new (current) contract
     */
    event LiquidationRewardsManagerUpdated(address newAddress);

    /**
     * @notice Emitted when the rebalancer contract is updated
     * @param newAddress The address of the new (current) contract
     */
    event RebalancerUpdated(address newAddress);

    /**
     * @notice Emitted when the pending protocol fee is distributed
     * @param feeCollector The collector's address
     * @param amount The amount of fee transferred
     */
    event ProtocolFeeDistributed(address feeCollector, uint256 amount);

    /**
     * @notice Emitted when the protocol fee is updated
     * @param feeBps The new fee in basis points
     */
    event FeeBpsUpdated(uint256 feeBps);

    /**
     * @notice Emitted when the fee collector is updated
     * @param feeCollector The new fee collector address
     */
    event FeeCollectorUpdated(address feeCollector);

    /**
     * @notice Emitted when the fee threshold is updated
     * @param feeThreshold The new fee threshold
     */
    event FeeThresholdUpdated(uint256 feeThreshold);

    /**
     * @notice Emitted when the target USDN price is updated
     * @param price The new target USDN price
     */
    event TargetUsdnPriceUpdated(uint128 price);

    /**
     * @notice Emitted when the USDN rebase threshold is updated
     * @param threshold The new target USDN price
     */
    event UsdnRebaseThresholdUpdated(uint128 threshold);

    /**
     * @notice Emitted when the USDN rebase interval is updated
     * @param interval The new interval
     */
    event UsdnRebaseIntervalUpdated(uint256 interval);

    /**
     * @notice Emitted when imbalance limits are updated
     * @param newOpenLimitBps The new open limit
     * @param newDepositLimitBps The new deposit limit
     * @param newWithdrawalLimitBps The new withdrawal limit
     * @param newCloseLimitBps The new close limit
     * @param newRebalancerCloseLimitBps The new close limit for the rebalancer's position
     * @param newLongImbalanceTargetBps The new long imbalance target
     */
    event ImbalanceLimitsUpdated(
        uint256 newOpenLimitBps,
        uint256 newDepositLimitBps,
        uint256 newWithdrawalLimitBps,
        uint256 newCloseLimitBps,
        uint256 newRebalancerCloseLimitBps,
        int256 newLongImbalanceTargetBps
    );

    /**
     * @notice Emitted when the minimum long position is updated
     * @param minLongPosition The new minimum long position
     */
    event MinLongPositionUpdated(uint256 minLongPosition);

    /**
     * @notice Emitted when the highest populated tick is updated
     * @param tick The new highest populated tick
     */
    event HighestPopulatedTickUpdated(int24 tick);

    /**
     * @notice Emitted when a security deposit is refunded
     * @param pendingActionValidator Address of the validator
     * @param receivedBy Address of the user who received the security deposit
     * @param amount Amount of security deposit refunded
     */
    event SecurityDepositRefunded(address indexed pendingActionValidator, address indexed receivedBy, uint256 amount);

    /**
     * @notice Emitted when a position changes ownership
     * @param posId The unique position ID
     * @param oldOwner The old owner
     * @param newOwner The new owner
     */
    event PositionOwnershipTransferred(PositionId indexed posId, address indexed oldOwner, address indexed newOwner);

    /**
     * @notice Emitted when the last funding per day is updated
     * @param lastFundingPerDay The new funding per day
     * @param lastUpdateTimestamp The timestamp for which the funding per day was calculated
     */
    event LastFundingPerDayUpdated(int256 lastFundingPerDay, uint256 lastUpdateTimestamp);
}

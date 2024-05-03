// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.0;

import { PositionId } from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";

/**
 * @title IUsdnProtocolEvents
 * @notice Events for the USDN Protocol
 */
interface IUsdnProtocolEvents {
    /**
     * @notice Emitted when a user initiates a deposit.
     * @param to The address that will receive the USDN tokens.
     * @param validator The address of the validator that will validate the deposit.
     * @param amount The amount of asset that were deposited.
     * @param timestamp The timestamp of the action.
     */
    event InitiatedDeposit(address indexed to, address indexed validator, uint256 amount, uint256 timestamp);

    /**
     * @notice Emitted when a user validates a deposit.
     * @param to The address that received the USDN tokens.
     * @param validator The address of the validator that validated the deposit.
     * @param amountDeposited The amount of asset that were deposited.
     * @param usdnMinted The amount of USDN that were minted.
     * @param timestamp The timestamp of the InitiatedDeposit action.
     */
    event ValidatedDeposit(
        address indexed to, address indexed validator, uint256 amountDeposited, uint256 usdnMinted, uint256 timestamp
    );

    /**
     * @notice Emitted when a user initiates a withdrawal.
     * @param to The address that will receive the assets.
     * @param validator The address of the validator that will validate the withdrawal.
     * @param usdnAmount The amount of USDN that will be burned.
     * @param timestamp The timestamp of the action.
     */
    event InitiatedWithdrawal(address indexed to, address indexed validator, uint256 usdnAmount, uint256 timestamp);

    /**
     * @notice Emitted when a user validates a withdrawal.
     * @param to The address that received the assets.
     * @param validator The address of the validator that validated the withdrawal.
     * @param amountWithdrawn The amount of asset that were withdrawn.
     * @param usdnBurned The amount of USDN that were burned.
     * @param timestamp The timestamp of the InitiatedWithdrawal action.
     */
    event ValidatedWithdrawal(
        address indexed to, address indexed validator, uint256 amountWithdrawn, uint256 usdnBurned, uint256 timestamp
    );

    /**
     * @notice Emitted when a user initiates the opening of a long position.
     * @dev The combination of the tick number, the tick version, and the index constitutes a unique identifier for the
     * position.
     * @param to The address that will be the owner of the position.
     * @param validator The address of the validator that will validate the position.
     * @param timestamp The timestamp of the action.
     * @param leverage The initial leverage of the position (pending validation).
     * @param amount The amount of asset that were deposited as collateral.
     * @param startPrice The asset price at the moment of the position creation (pending validation).
     * @param posId The unique position identifier
     */
    event InitiatedOpenPosition(
        address indexed to,
        address indexed validator,
        uint40 timestamp,
        uint128 leverage,
        uint128 amount,
        uint128 startPrice,
        PositionId posId
    );

    /**
     * @notice Emitted when a user validates the opening of a long position.
     * @param to The address that will be the owner of the position.
     * @param validator The address of the validator that validated the position.
     * @param newLeverage The initial leverage of the position (final).
     * @param newStartPrice The asset price at the moment of the position creation (final).
     * @param posId The unique position identifier
     * If changed compared to `InitiatedOpenLong`, then `LiquidationPriceUpdated` will be emitted too
     */
    event ValidatedOpenPosition(
        address indexed to, address indexed validator, uint128 newLeverage, uint128 newStartPrice, PositionId posId
    );

    /**
     * @notice Emitted when a position was moved from one tick to another
     * @param oldPosId The old position identifier
     * @param newPosId The new position identifier
     */
    event LiquidationPriceUpdated(PositionId indexed oldPosId, PositionId newPosId);

    /**
     * @notice Emitted when a user initiates the closing of all or part of a long position.
     * @param to The address that will receive the assets.
     * @param validator The address of the validator that will validate the position.
     * @param posId The unique position identifier
     * @param originalAmount The amount of collateral originally on the position.
     * @param amountToClose The amount of collateral to close from the position.
     * If the entirety of the position is being closed, this value equals originalAmount.
     * @param totalExpoRemaining The total expo remaining in the position.
     * If the entirety of the position is being closed, this value is zero.
     */
    event InitiatedClosePosition(
        address indexed to,
        address indexed validator,
        PositionId posId,
        uint128 originalAmount,
        uint128 amountToClose,
        uint128 totalExpoRemaining
    );

    /**
     * @notice Emitted when a user validates the closing of a long position
     * @param to The address that received the assets.
     * @param validator The address of the validator that validated the position.
     * @param posId The unique position identifier
     * @param amountReceived The amount of asset that were sent to the user.
     * @param profit The profit that the user made.
     */
    event ValidatedClosePosition(
        address indexed to, address indexed validator, PositionId posId, uint256 amountReceived, int256 profit
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
     * @param user The user address
     * @param posId The unique identifier for the position that was liquidated
     * @param liquidationPrice The asset price at the moment of liquidation
     * @param effectiveTickPrice The effective liquidated tick price
     */
    event LiquidatedPosition(
        address indexed user, PositionId posId, uint256 liquidationPrice, uint256 effectiveTickPrice
    );

    /**
     * @notice Emitted when a user's position was liquidated while pending validation and we remove the pending action
     * @param user The user address
     * @param posId The unique position identifier
     */
    event StalePendingActionRemoved(address indexed user, PositionId posId);

    /**
     * @notice Emitted when the position fees are updated
     * @param positionFee The new position fee (in percentage)
     */
    event PositionFeeUpdated(uint256 positionFee);

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
     * @notice Emitted when the minLeverage is updated
     * @param newMinLeverage The new minLeverage
     */
    event MinLeverageUpdated(uint256 newMinLeverage);

    /**
     * @notice Emitted when the maxLeverage is updated
     * @param newMaxLeverage The new maxLeverage
     */
    event MaxLeverageUpdated(uint256 newMaxLeverage);

    /**
     * @notice Emitted when the validationDeadline is updated
     * @param newValidationDeadline The new validationDeadline
     */
    event ValidationDeadlineUpdated(uint256 newValidationDeadline);

    /**
     * @notice Emitted when the liquidationPenalty is updated
     * @param newLiquidationPenalty The new liquidationPenalty
     */
    event LiquidationPenaltyUpdated(uint8 newLiquidationPenalty);

    /**
     * @notice Emitted when the safetyMargin is updated
     * @param newSafetyMargin The new safetyMargin
     */
    event SafetyMarginBpsUpdated(uint256 newSafetyMargin);

    /**
     * @notice Emitted when the liquidationIteration is updated
     * @param newLiquidationIteration The new liquidationIteration
     */
    event LiquidationIterationUpdated(uint16 newLiquidationIteration);

    /**
     * @notice Emitted when the EMAPeriod is updated
     * @param newEMAPeriod The new EMAPeriod
     */
    event EMAPeriodUpdated(uint128 newEMAPeriod);

    /**
     * @notice Emitted when the fundingSF is updated
     * @param newFundingSF The new fundingSF
     */
    event FundingSFUpdated(uint256 newFundingSF);

    /**
     * @notice Emitted when a user (liquidator) successfully liquidated positions
     * @param liquidator The address that initiated the liquidation
     * @param rewards The amount of tokens the liquidator received in rewards
     */
    event LiquidatorRewarded(address indexed liquidator, uint256 rewards);

    /**
     * @notice Emitted when the LiquidationRewardsManager contract is updated
     * @param newAddress The address of the new (current) contract
     */
    event LiquidationRewardsManagerUpdated(address newAddress);

    /**
     * @notice Emitted when the OrderManager contract is updated
     * @param newAddress The address of the new (current) contract
     */
    event OrderManagerUpdated(address newAddress);

    /**
     * @notice Emitted when the pending protocol fee is distributed
     * @param feeCollector The collector address
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
     */
    event ImbalanceLimitsUpdated(
        uint256 newOpenLimitBps, uint256 newDepositLimitBps, uint256 newWithdrawalLimitBps, uint256 newCloseLimitBps
    );

    /**
     * @notice Emitted when the minimum long position is updated
     * @param minLongPosition The new minimum long position
     */
    event MinLongPositionUpdated(uint256 minLongPosition);

    /**
     * @notice Emitted when a security deposit is refunded
     * @param paidBy Address of the user who paid the security deposit
     * @param receivedBy Address of the user who received the security deposit
     * @param amount Amount of security deposit refunded
     */
    event SecurityDepositRefunded(address indexed paidBy, address indexed receivedBy, uint256 amount);
}

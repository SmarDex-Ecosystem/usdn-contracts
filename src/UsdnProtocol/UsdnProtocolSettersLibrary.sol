// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.25;

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { SafeTransferLib } from "solady/src/utils/SafeTransferLib.sol";

import { IUsdnProtocol } from "../interfaces/UsdnProtocol/IUsdnProtocol.sol";
import { ILiquidationRewardsManager } from "../interfaces/OracleMiddleware/ILiquidationRewardsManager.sol";
import { IBaseOracleMiddleware } from "../interfaces/OracleMiddleware/IBaseOracleMiddleware.sol";
import { IBaseRebalancer } from "../interfaces/Rebalancer/IBaseRebalancer.sol";
import { UsdnProtocolBaseStorage } from "./UsdnProtocolBaseStorage.sol";
import { IUsdnProtocolErrors } from "./../interfaces/UsdnProtocol/IUsdnProtocolErrors.sol";
import { Storage } from "./UsdnProtocolBaseStorage.sol";
import { PositionId } from "../interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";

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
event LiquidatedPosition(address indexed user, PositionId posId, uint256 liquidationPrice, uint256 effectiveTickPrice);

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
event LiquidationPenaltyUpdated(uint8 newLiquidationPenalty);

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
 * @param newLongImbalanceTargetBps The new long imbalance target
 */
event ImbalanceLimitsUpdated(
    uint256 newOpenLimitBps,
    uint256 newDepositLimitBps,
    uint256 newWithdrawalLimitBps,
    uint256 newCloseLimitBps,
    int256 newLongImbalanceTargetBps
);

/**
 * @notice Emitted when the minimum long position is updated
 * @param minLongPosition The new minimum long position
 */
event MinLongPositionUpdated(uint256 minLongPosition);

library UsdnProtocolSettersLibrary {
    using SafeTransferLib for address;
    using SafeCast for uint256;

    // / @inheritdoc IUsdnProtocol
    function setOracleMiddleware(Storage storage s, IBaseOracleMiddleware newOracleMiddleware) external {
        if (address(newOracleMiddleware) == address(0)) {
            revert IUsdnProtocolErrors.UsdnProtocolInvalidMiddlewareAddress();
        }
        s._oracleMiddleware = newOracleMiddleware;
        emit OracleMiddlewareUpdated(address(newOracleMiddleware));
    }

    // / @inheritdoc IUsdnProtocol
    function setLiquidationRewardsManager(Storage storage s, ILiquidationRewardsManager newLiquidationRewardsManager)
        external
    {
        if (address(newLiquidationRewardsManager) == address(0)) {
            revert IUsdnProtocolErrors.UsdnProtocolInvalidLiquidationRewardsManagerAddress();
        }

        s._liquidationRewardsManager = newLiquidationRewardsManager;

        emit LiquidationRewardsManagerUpdated(address(newLiquidationRewardsManager));
    }

    // / @inheritdoc IUsdnProtocol
    function setRebalancer(Storage storage s, IBaseRebalancer newRebalancer) external {
        s._rebalancer = newRebalancer;

        emit RebalancerUpdated(address(newRebalancer));
    }

    // / @inheritdoc IUsdnProtocol
    function setMinLeverage(Storage storage s, uint256 newMinLeverage) external {
        // zero minLeverage
        if (newMinLeverage <= 10 ** s.LEVERAGE_DECIMALS) {
            revert IUsdnProtocolErrors.UsdnProtocolInvalidMinLeverage();
        }

        if (newMinLeverage >= s._maxLeverage) {
            revert IUsdnProtocolErrors.UsdnProtocolInvalidMinLeverage();
        }

        s._minLeverage = newMinLeverage;
        emit MinLeverageUpdated(newMinLeverage);
    }

    // / @inheritdoc IUsdnProtocol
    function setMaxLeverage(Storage storage s, uint256 newMaxLeverage) external {
        if (newMaxLeverage <= s._minLeverage) {
            revert IUsdnProtocolErrors.UsdnProtocolInvalidMaxLeverage();
        }

        // `maxLeverage` greater than 100
        if (newMaxLeverage > 100 * 10 ** s.LEVERAGE_DECIMALS) {
            revert IUsdnProtocolErrors.UsdnProtocolInvalidMaxLeverage();
        }

        s._maxLeverage = newMaxLeverage;
        emit MaxLeverageUpdated(newMaxLeverage);
    }

    // / @inheritdoc IUsdnProtocol
    function setValidationDeadline(Storage storage s, uint256 newValidationDeadline) external {
        if (newValidationDeadline < 60) {
            revert IUsdnProtocolErrors.UsdnProtocolInvalidValidationDeadline();
        }

        if (newValidationDeadline > 1 days) {
            revert IUsdnProtocolErrors.UsdnProtocolInvalidValidationDeadline();
        }

        s._validationDeadline = newValidationDeadline;
        emit ValidationDeadlineUpdated(newValidationDeadline);
    }

    // / @inheritdoc IUsdnProtocol
    function setLiquidationPenalty(Storage storage s, uint8 newLiquidationPenalty) external {
        if (newLiquidationPenalty > 15) {
            revert IUsdnProtocolErrors.UsdnProtocolInvalidLiquidationPenalty();
        }

        s._liquidationPenalty = newLiquidationPenalty;
        emit LiquidationPenaltyUpdated(newLiquidationPenalty);
    }

    // / @inheritdoc IUsdnProtocol
    function setSafetyMarginBps(Storage storage s, uint256 newSafetyMarginBps) external {
        // safetyMarginBps greater than 20%
        if (newSafetyMarginBps > 2000) {
            revert IUsdnProtocolErrors.UsdnProtocolInvalidSafetyMarginBps();
        }

        s._safetyMarginBps = newSafetyMarginBps;
        emit SafetyMarginBpsUpdated(newSafetyMarginBps);
    }

    // / @inheritdoc IUsdnProtocol
    function setLiquidationIteration(Storage storage s, uint16 newLiquidationIteration) external {
        if (newLiquidationIteration > s.MAX_LIQUIDATION_ITERATION) {
            revert IUsdnProtocolErrors.UsdnProtocolInvalidLiquidationIteration();
        }

        s._liquidationIteration = newLiquidationIteration;
        emit LiquidationIterationUpdated(newLiquidationIteration);
    }

    // / @inheritdoc IUsdnProtocol
    function setEMAPeriod(Storage storage s, uint128 newEMAPeriod) external {
        if (newEMAPeriod > 90 days) {
            revert IUsdnProtocolErrors.UsdnProtocolInvalidEMAPeriod();
        }

        s._EMAPeriod = newEMAPeriod;
        emit EMAPeriodUpdated(newEMAPeriod);
    }

    // / @inheritdoc IUsdnProtocol
    function setFundingSF(Storage storage s, uint256 newFundingSF) external {
        if (newFundingSF > 10 ** s.FUNDING_SF_DECIMALS) {
            revert IUsdnProtocolErrors.UsdnProtocolInvalidFundingSF();
        }

        s._fundingSF = newFundingSF;
        emit FundingSFUpdated(newFundingSF);
    }

    // / @inheritdoc IUsdnProtocol
    function setProtocolFeeBps(Storage storage s, uint16 newProtocolFeeBps) external {
        if (newProtocolFeeBps > s.BPS_DIVISOR) {
            revert IUsdnProtocolErrors.UsdnProtocolInvalidProtocolFeeBps();
        }
        s._protocolFeeBps = newProtocolFeeBps;
        emit FeeBpsUpdated(newProtocolFeeBps);
    }

    // / @inheritdoc IUsdnProtocol
    function setPositionFeeBps(Storage storage s, uint16 newPositionFee) external {
        // `newPositionFee` greater than 20%
        if (newPositionFee > 2000) {
            revert IUsdnProtocolErrors.UsdnProtocolInvalidPositionFee();
        }
        s._positionFeeBps = newPositionFee;
        emit PositionFeeUpdated(newPositionFee);
    }

    // / @inheritdoc IUsdnProtocol
    function setVaultFeeBps(Storage storage s, uint16 newVaultFee) external {
        // `newVaultFee` greater than 20%
        if (newVaultFee > 2000) {
            revert IUsdnProtocolErrors.UsdnProtocolInvalidVaultFee();
        }
        s._vaultFeeBps = newVaultFee;
        emit VaultFeeUpdated(newVaultFee);
    }

    // / @inheritdoc IUsdnProtocol
    function setRebalancerBonusBps(Storage storage s, uint16 newBonus) external {
        // `newBonus` greater than 100%
        if (newBonus > s.BPS_DIVISOR) {
            revert IUsdnProtocolErrors.UsdnProtocolInvalidRebalancerBonus();
        }
        s._rebalancerBonusBps = newBonus;
        emit RebalancerBonusUpdated(newBonus);
    }

    // / @inheritdoc IUsdnProtocol
    function setSdexBurnOnDepositRatio(Storage storage s, uint32 newRatio) external {
        // `newRatio` greater than 5%
        if (newRatio > s.SDEX_BURN_ON_DEPOSIT_DIVISOR / 20) {
            revert IUsdnProtocolErrors.UsdnProtocolInvalidBurnSdexOnDepositRatio();
        }

        s._sdexBurnOnDepositRatio = newRatio;

        emit BurnSdexOnDepositRatioUpdated(newRatio);
    }

    // / @inheritdoc IUsdnProtocol
    function setSecurityDepositValue(Storage storage s, uint64 securityDepositValue) external {
        s._securityDepositValue = securityDepositValue;
        emit SecurityDepositValueUpdated(securityDepositValue);
    }

    // / @inheritdoc IUsdnProtocol
    function setFeeThreshold(Storage storage s, uint256 newFeeThreshold) external {
        s._feeThreshold = newFeeThreshold;
        emit FeeThresholdUpdated(newFeeThreshold);
    }

    // / @inheritdoc IUsdnProtocol
    function setFeeCollector(Storage storage s, address newFeeCollector) external {
        if (newFeeCollector == address(0)) {
            revert IUsdnProtocolErrors.UsdnProtocolInvalidFeeCollector();
        }
        s._feeCollector = newFeeCollector;
        emit FeeCollectorUpdated(newFeeCollector);
    }

    // / @inheritdoc IUsdnProtocol
    function setExpoImbalanceLimits(
        Storage storage s,
        uint256 newOpenLimitBps,
        uint256 newDepositLimitBps,
        uint256 newWithdrawalLimitBps,
        uint256 newCloseLimitBps,
        int256 newLongImbalanceTargetBps
    ) external {
        s._openExpoImbalanceLimitBps = newOpenLimitBps.toInt256();
        s._depositExpoImbalanceLimitBps = newDepositLimitBps.toInt256();

        if (newWithdrawalLimitBps != 0 && newWithdrawalLimitBps < newOpenLimitBps) {
            // withdrawal limit lower than open not permitted
            revert IUsdnProtocolErrors.UsdnProtocolInvalidExpoImbalanceLimit();
        }
        s._withdrawalExpoImbalanceLimitBps = newWithdrawalLimitBps.toInt256();

        if (newCloseLimitBps != 0 && newCloseLimitBps < newDepositLimitBps) {
            // close limit lower than deposit not permitted
            revert IUsdnProtocolErrors.UsdnProtocolInvalidExpoImbalanceLimit();
        }
        s._closeExpoImbalanceLimitBps = newCloseLimitBps.toInt256();

        // casts are safe here as values are safely casted earlier
        if (
            newLongImbalanceTargetBps > int256(newCloseLimitBps)
                || newLongImbalanceTargetBps < -int256(newWithdrawalLimitBps)
                || newLongImbalanceTargetBps < -int256(s.BPS_DIVISOR / 2) // The target cannot be lower than -50%
        ) {
            revert IUsdnProtocolErrors.UsdnProtocolInvalidLongImbalanceTarget();
        }

        s._longImbalanceTargetBps = newLongImbalanceTargetBps;

        emit ImbalanceLimitsUpdated(
            newOpenLimitBps, newDepositLimitBps, newWithdrawalLimitBps, newCloseLimitBps, newLongImbalanceTargetBps
        );
    }

    // / @inheritdoc IUsdnProtocol
    function setTargetUsdnPrice(Storage storage s, uint128 newPrice) external {
        if (newPrice > s._usdnRebaseThreshold) {
            revert IUsdnProtocolErrors.UsdnProtocolInvalidTargetUsdnPrice();
        }
        if (newPrice < uint128(10 ** s._priceFeedDecimals)) {
            // values smaller than $1 are not allowed
            revert IUsdnProtocolErrors.UsdnProtocolInvalidTargetUsdnPrice();
        }
        s._targetUsdnPrice = newPrice;
        emit TargetUsdnPriceUpdated(newPrice);
    }

    // / @inheritdoc IUsdnProtocol
    function setUsdnRebaseThreshold(Storage storage s, uint128 newThreshold) external {
        if (newThreshold < s._targetUsdnPrice) {
            revert IUsdnProtocolErrors.UsdnProtocolInvalidUsdnRebaseThreshold();
        }
        s._usdnRebaseThreshold = newThreshold;
        emit UsdnRebaseThresholdUpdated(newThreshold);
    }

    // / @inheritdoc IUsdnProtocol
    function setUsdnRebaseInterval(Storage storage s, uint256 newInterval) external {
        s._usdnRebaseInterval = newInterval;
        emit UsdnRebaseIntervalUpdated(newInterval);
    }

    // / @inheritdoc IUsdnProtocol
    function setMinLongPosition(Storage storage s, uint256 newMinLongPosition) external {
        s._minLongPosition = newMinLongPosition;
        emit MinLongPositionUpdated(newMinLongPosition);

        IBaseRebalancer rebalancer = s._rebalancer;
        if (address(rebalancer) != address(0) && rebalancer.getMinAssetDeposit() < newMinLongPosition) {
            rebalancer.setMinAssetDeposit(newMinLongPosition);
        }
    }
}

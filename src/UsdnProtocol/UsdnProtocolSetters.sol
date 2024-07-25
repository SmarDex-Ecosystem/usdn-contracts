// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.25;

import { AccessControlDefaultAdminRules } from
    "@openzeppelin/contracts/access/extensions/AccessControlDefaultAdminRules.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import { IBaseOracleMiddleware } from "../interfaces/OracleMiddleware/IBaseOracleMiddleware.sol";
import { ILiquidationRewardsManager } from "../interfaces/OracleMiddleware/ILiquidationRewardsManager.sol";
import { IBaseRebalancer } from "../interfaces/Rebalancer/IBaseRebalancer.sol";
import { IUsdnProtocolErrors } from "../interfaces/UsdnProtocol/IUsdnProtocolErrors.sol";
import { IUsdnProtocolEvents } from "../interfaces/UsdnProtocol/IUsdnProtocolEvents.sol";
import { IUsdnProtocolSetters } from "../interfaces/UsdnProtocol/IUsdnProtocolSetters.sol";
import { UsdnProtocolStorage } from "./UsdnProtocolStorage.sol";
import { UsdnProtocolConstantsLibrary as Constants } from "./libraries/UsdnProtocolConstantsLibrary.sol";
import { UsdnProtocolConstantsLibrary as Constants } from "./libraries/UsdnProtocolConstantsLibrary.sol";
import { UsdnProtocolUtils as Utils } from "./libraries/UsdnProtocolUtils.sol";

contract UsdnProtocolSetters is IUsdnProtocolSetters, UsdnProtocolStorage {
    using SafeCast for uint256;

    constructor() AccessControlDefaultAdminRules(0, msg.sender) { }

    /* -------------------------------------------------------------------------- */
    /*                              SET_EXTERNAL_ROLE                             */
    /* -------------------------------------------------------------------------- */

    /// @inheritdoc IUsdnProtocolSetters
    function setOracleMiddleware(IBaseOracleMiddleware newOracleMiddleware) external onlyRole(SET_EXTERNAL_ROLE) {
        if (address(newOracleMiddleware) == address(0)) {
            revert IUsdnProtocolErrors.UsdnProtocolInvalidMiddlewareAddress();
        }
        s._oracleMiddleware = newOracleMiddleware;
        emit IUsdnProtocolEvents.OracleMiddlewareUpdated(address(newOracleMiddleware));
    }

    /// @inheritdoc IUsdnProtocolSetters
    function setLiquidationRewardsManager(ILiquidationRewardsManager newLiquidationRewardsManager)
        external
        onlyRole(SET_EXTERNAL_ROLE)
    {
        if (address(newLiquidationRewardsManager) == address(0)) {
            revert IUsdnProtocolErrors.UsdnProtocolInvalidLiquidationRewardsManagerAddress();
        }

        s._liquidationRewardsManager = newLiquidationRewardsManager;

        emit IUsdnProtocolEvents.LiquidationRewardsManagerUpdated(address(newLiquidationRewardsManager));
    }

    /// @inheritdoc IUsdnProtocolSetters
    function setRebalancer(IBaseRebalancer newRebalancer) external onlyRole(SET_EXTERNAL_ROLE) {
        s._rebalancer = newRebalancer;

        emit IUsdnProtocolEvents.RebalancerUpdated(address(newRebalancer));
    }

    /// @inheritdoc IUsdnProtocolSetters
    function setFeeCollector(address newFeeCollector) external onlyRole(SET_EXTERNAL_ROLE) {
        if (newFeeCollector == address(0)) {
            revert IUsdnProtocolErrors.UsdnProtocolInvalidFeeCollector();
        }
        s._feeCollector = newFeeCollector;
        emit IUsdnProtocolEvents.FeeCollectorUpdated(newFeeCollector);
    }

    /* -------------------------------------------------------------------------- */
    /*                           CRITICAL_FUNCTIONS_ROLE                          */
    /* -------------------------------------------------------------------------- */

    /// @inheritdoc IUsdnProtocolSetters
    function setValidationDeadline(uint256 newValidationDeadline) external onlyRole(CRITICAL_FUNCTIONS_ROLE) {
        if (newValidationDeadline < 60) {
            revert IUsdnProtocolErrors.UsdnProtocolInvalidValidationDeadline();
        }

        if (newValidationDeadline > 1 days) {
            revert IUsdnProtocolErrors.UsdnProtocolInvalidValidationDeadline();
        }

        s._validationDeadline = newValidationDeadline;
        emit IUsdnProtocolEvents.ValidationDeadlineUpdated(newValidationDeadline);
    }

    /* -------------------------------------------------------------------------- */
    /*                          SET_PROTOCOL_PARAMS_ROLE                          */
    /* -------------------------------------------------------------------------- */

    /// @inheritdoc IUsdnProtocolSetters
    function setMinLeverage(uint256 newMinLeverage) external onlyRole(SET_PROTOCOL_PARAMS_ROLE) {
        // zero minLeverage
        if (newMinLeverage <= 10 ** Constants.LEVERAGE_DECIMALS) {
            revert IUsdnProtocolErrors.UsdnProtocolInvalidMinLeverage();
        }

        if (newMinLeverage >= s._maxLeverage) {
            revert IUsdnProtocolErrors.UsdnProtocolInvalidMinLeverage();
        }

        s._minLeverage = newMinLeverage;
        emit IUsdnProtocolEvents.MinLeverageUpdated(newMinLeverage);
    }

    /// @inheritdoc IUsdnProtocolSetters
    function setMaxLeverage(uint256 newMaxLeverage) external onlyRole(SET_PROTOCOL_PARAMS_ROLE) {
        if (newMaxLeverage <= s._minLeverage) {
            revert IUsdnProtocolErrors.UsdnProtocolInvalidMaxLeverage();
        }

        // `maxLeverage` greater than 100
        if (newMaxLeverage > 100 * 10 ** Constants.LEVERAGE_DECIMALS) {
            revert IUsdnProtocolErrors.UsdnProtocolInvalidMaxLeverage();
        }

        s._maxLeverage = newMaxLeverage;
        emit IUsdnProtocolEvents.MaxLeverageUpdated(newMaxLeverage);
    }

    /// @inheritdoc IUsdnProtocolSetters
    function setLiquidationPenalty(uint8 newLiquidationPenalty) external onlyRole(SET_PROTOCOL_PARAMS_ROLE) {
        if (newLiquidationPenalty > 15) {
            revert IUsdnProtocolErrors.UsdnProtocolInvalidLiquidationPenalty();
        }

        s._liquidationPenalty = newLiquidationPenalty;
        emit IUsdnProtocolEvents.LiquidationPenaltyUpdated(newLiquidationPenalty);
    }

    /// @inheritdoc IUsdnProtocolSetters
    function setEMAPeriod(uint128 newEMAPeriod) external onlyRole(SET_PROTOCOL_PARAMS_ROLE) {
        if (newEMAPeriod > 90 days) {
            revert IUsdnProtocolErrors.UsdnProtocolInvalidEMAPeriod();
        }

        s._EMAPeriod = newEMAPeriod;
        emit IUsdnProtocolEvents.EMAPeriodUpdated(newEMAPeriod);
    }

    /// @inheritdoc IUsdnProtocolSetters
    function setFundingSF(uint256 newFundingSF) external onlyRole(SET_PROTOCOL_PARAMS_ROLE) {
        if (newFundingSF > 10 ** Constants.FUNDING_SF_DECIMALS) {
            revert IUsdnProtocolErrors.UsdnProtocolInvalidFundingSF();
        }

        s._fundingSF = newFundingSF;
        emit IUsdnProtocolEvents.FundingSFUpdated(newFundingSF);
    }

    /// @inheritdoc IUsdnProtocolSetters
    function setProtocolFeeBps(uint16 newProtocolFeeBps) external onlyRole(SET_PROTOCOL_PARAMS_ROLE) {
        if (newProtocolFeeBps > Constants.BPS_DIVISOR) {
            revert IUsdnProtocolErrors.UsdnProtocolInvalidProtocolFeeBps();
        }
        s._protocolFeeBps = newProtocolFeeBps;
        emit IUsdnProtocolEvents.FeeBpsUpdated(newProtocolFeeBps);
    }

    /// @inheritdoc IUsdnProtocolSetters
    function setPositionFeeBps(uint16 newPositionFee) external onlyRole(SET_PROTOCOL_PARAMS_ROLE) {
        // `newPositionFee` greater than 20%
        if (newPositionFee > 2000) {
            revert IUsdnProtocolErrors.UsdnProtocolInvalidPositionFee();
        }
        s._positionFeeBps = newPositionFee;
        emit IUsdnProtocolEvents.PositionFeeUpdated(newPositionFee);
    }

    /// @inheritdoc IUsdnProtocolSetters
    function setVaultFeeBps(uint16 newVaultFee) external onlyRole(SET_PROTOCOL_PARAMS_ROLE) {
        // `newVaultFee` greater than 20%
        if (newVaultFee > 2000) {
            revert IUsdnProtocolErrors.UsdnProtocolInvalidVaultFee();
        }
        s._vaultFeeBps = newVaultFee;
        emit IUsdnProtocolEvents.VaultFeeUpdated(newVaultFee);
    }

    /// @inheritdoc IUsdnProtocolSetters
    function setRebalancerBonusBps(uint16 newBonus) external onlyRole(SET_PROTOCOL_PARAMS_ROLE) {
        // `newBonus` greater than 100%
        if (newBonus > Constants.BPS_DIVISOR) {
            revert IUsdnProtocolErrors.UsdnProtocolInvalidRebalancerBonus();
        }
        s._rebalancerBonusBps = newBonus;
        emit IUsdnProtocolEvents.RebalancerBonusUpdated(newBonus);
    }

    /// @inheritdoc IUsdnProtocolSetters
    function setSdexBurnOnDepositRatio(uint32 newRatio) external onlyRole(SET_PROTOCOL_PARAMS_ROLE) {
        // `newRatio` greater than 5%
        if (newRatio > Constants.SDEX_BURN_ON_DEPOSIT_DIVISOR / 20) {
            revert IUsdnProtocolErrors.UsdnProtocolInvalidBurnSdexOnDepositRatio();
        }

        s._sdexBurnOnDepositRatio = newRatio;

        emit IUsdnProtocolEvents.BurnSdexOnDepositRatioUpdated(newRatio);
    }

    /// @inheritdoc IUsdnProtocolSetters
    function setSecurityDepositValue(uint64 securityDepositValue) external onlyRole(SET_PROTOCOL_PARAMS_ROLE) {
        s._securityDepositValue = securityDepositValue;
        emit IUsdnProtocolEvents.SecurityDepositValueUpdated(securityDepositValue);
    }

    /// @inheritdoc IUsdnProtocolSetters
    function setExpoImbalanceLimits(
        uint256 newOpenLimitBps,
        uint256 newDepositLimitBps,
        uint256 newWithdrawalLimitBps,
        uint256 newCloseLimitBps,
        int256 newLongImbalanceTargetBps
    ) external onlyRole(SET_PROTOCOL_PARAMS_ROLE) {
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
                || newLongImbalanceTargetBps < -int256(Constants.BPS_DIVISOR / 2) // The target cannot be lower than -50%
        ) {
            revert IUsdnProtocolErrors.UsdnProtocolInvalidLongImbalanceTarget();
        }

        s._longImbalanceTargetBps = newLongImbalanceTargetBps;

        emit IUsdnProtocolEvents.ImbalanceLimitsUpdated(
            newOpenLimitBps, newDepositLimitBps, newWithdrawalLimitBps, newCloseLimitBps, newLongImbalanceTargetBps
        );
    }

    /// @inheritdoc IUsdnProtocolSetters
    function setMinLongPosition(uint256 newMinLongPosition) external onlyRole(SET_PROTOCOL_PARAMS_ROLE) {
        s._minLongPosition = newMinLongPosition;
        emit IUsdnProtocolEvents.MinLongPositionUpdated(newMinLongPosition);

        IBaseRebalancer rebalancer = s._rebalancer;
        if (address(rebalancer) != address(0) && rebalancer.getMinAssetDeposit() < newMinLongPosition) {
            rebalancer.setMinAssetDeposit(newMinLongPosition);
        }
    }

    /* -------------------------------------------------------------------------- */
    /*                              SET_OPTIONS_ROLE                              */
    /* -------------------------------------------------------------------------- */

    /// @inheritdoc IUsdnProtocolSetters
    function setSafetyMarginBps(uint256 newSafetyMarginBps) external onlyRole(SET_OPTIONS_ROLE) {
        // safetyMarginBps greater than 20%
        if (newSafetyMarginBps > 2000) {
            revert IUsdnProtocolErrors.UsdnProtocolInvalidSafetyMarginBps();
        }

        s._safetyMarginBps = newSafetyMarginBps;
        emit IUsdnProtocolEvents.SafetyMarginBpsUpdated(newSafetyMarginBps);
    }

    /// @inheritdoc IUsdnProtocolSetters
    function setLiquidationIteration(uint16 newLiquidationIteration) external onlyRole(SET_OPTIONS_ROLE) {
        if (newLiquidationIteration > Constants.MAX_LIQUIDATION_ITERATION) {
            revert IUsdnProtocolErrors.UsdnProtocolInvalidLiquidationIteration();
        }

        s._liquidationIteration = newLiquidationIteration;
        emit IUsdnProtocolEvents.LiquidationIterationUpdated(newLiquidationIteration);
    }

    /// @inheritdoc IUsdnProtocolSetters
    function setFeeThreshold(uint256 newFeeThreshold) external onlyRole(SET_OPTIONS_ROLE) {
        s._feeThreshold = newFeeThreshold;
        emit IUsdnProtocolEvents.FeeThresholdUpdated(newFeeThreshold);
    }

    /* -------------------------------------------------------------------------- */
    /*                            SET_USDN_PARAMS_ROLE                            */
    /* -------------------------------------------------------------------------- */

    /// @inheritdoc IUsdnProtocolSetters
    function setTargetUsdnPrice(uint128 newPrice) external onlyRole(SET_USDN_PARAMS_ROLE) {
        if (newPrice > s._usdnRebaseThreshold) {
            revert IUsdnProtocolErrors.UsdnProtocolInvalidTargetUsdnPrice();
        }
        if (newPrice < uint128(10 ** s._priceFeedDecimals)) {
            // values smaller than $1 are not allowed
            revert IUsdnProtocolErrors.UsdnProtocolInvalidTargetUsdnPrice();
        }
        s._targetUsdnPrice = newPrice;
        emit IUsdnProtocolEvents.TargetUsdnPriceUpdated(newPrice);
    }

    /// @inheritdoc IUsdnProtocolSetters
    function setUsdnRebaseThreshold(uint128 newThreshold) external onlyRole(SET_USDN_PARAMS_ROLE) {
        if (newThreshold < s._targetUsdnPrice) {
            revert IUsdnProtocolErrors.UsdnProtocolInvalidUsdnRebaseThreshold();
        }
        s._usdnRebaseThreshold = newThreshold;
        emit IUsdnProtocolEvents.UsdnRebaseThresholdUpdated(newThreshold);
    }

    /// @inheritdoc IUsdnProtocolSetters
    function setUsdnRebaseInterval(uint256 newInterval) external onlyRole(SET_USDN_PARAMS_ROLE) {
        s._usdnRebaseInterval = newInterval;
        emit IUsdnProtocolEvents.UsdnRebaseIntervalUpdated(newInterval);
    }
}

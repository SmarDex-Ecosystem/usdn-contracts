// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.25;

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { SafeTransferLib } from "solady/src/utils/SafeTransferLib.sol";

import { IUsdnProtocol } from "../../interfaces/UsdnProtocol/IUsdnProtocol.sol";
import { ILiquidationRewardsManager } from "../../interfaces/OracleMiddleware/ILiquidationRewardsManager.sol";
import { IBaseOracleMiddleware } from "../../interfaces/OracleMiddleware/IBaseOracleMiddleware.sol";
import { IBaseRebalancer } from "../../interfaces/Rebalancer/IBaseRebalancer.sol";
import { UsdnProtocolStorage } from "../UsdnProtocolStorage.sol";
import { IUsdnProtocolEvents } from "./../../interfaces/UsdnProtocol/IUsdnProtocolEvents.sol";
import { IUsdnProtocolErrors } from "./../../interfaces/UsdnProtocol/IUsdnProtocolErrors.sol";
import { Storage } from "./../UsdnProtocolStorage.sol";

library UsdnProtocolSettersLibrary {
    using SafeTransferLib for address;
    using SafeCast for uint256;

    /// @notice See {IUsdnProtocol}
    function setOracleMiddleware(Storage storage s, IBaseOracleMiddleware newOracleMiddleware) external {
        if (address(newOracleMiddleware) == address(0)) {
            revert IUsdnProtocolErrors.UsdnProtocolInvalidMiddlewareAddress();
        }
        s._oracleMiddleware = newOracleMiddleware;
        emit IUsdnProtocolEvents.OracleMiddlewareUpdated(address(newOracleMiddleware));
    }

    /// @notice See {IUsdnProtocol}
    function setLiquidationRewardsManager(Storage storage s, ILiquidationRewardsManager newLiquidationRewardsManager)
        external
    {
        if (address(newLiquidationRewardsManager) == address(0)) {
            revert IUsdnProtocolErrors.UsdnProtocolInvalidLiquidationRewardsManagerAddress();
        }

        s._liquidationRewardsManager = newLiquidationRewardsManager;

        emit IUsdnProtocolEvents.LiquidationRewardsManagerUpdated(address(newLiquidationRewardsManager));
    }

    /// @notice See {IUsdnProtocol}
    function setRebalancer(Storage storage s, IBaseRebalancer newRebalancer) external {
        s._rebalancer = newRebalancer;

        emit IUsdnProtocolEvents.RebalancerUpdated(address(newRebalancer));
    }

    /// @notice See {IUsdnProtocol}
    function setMinLeverage(Storage storage s, uint256 newMinLeverage) external {
        // zero minLeverage
        if (newMinLeverage <= 10 ** s.LEVERAGE_DECIMALS) {
            revert IUsdnProtocolErrors.UsdnProtocolInvalidMinLeverage();
        }

        if (newMinLeverage >= s._maxLeverage) {
            revert IUsdnProtocolErrors.UsdnProtocolInvalidMinLeverage();
        }

        s._minLeverage = newMinLeverage;
        emit IUsdnProtocolEvents.MinLeverageUpdated(newMinLeverage);
    }

    /// @notice See {IUsdnProtocol}
    function setMaxLeverage(Storage storage s, uint256 newMaxLeverage) external {
        if (newMaxLeverage <= s._minLeverage) {
            revert IUsdnProtocolErrors.UsdnProtocolInvalidMaxLeverage();
        }

        // `maxLeverage` greater than 100
        if (newMaxLeverage > 100 * 10 ** s.LEVERAGE_DECIMALS) {
            revert IUsdnProtocolErrors.UsdnProtocolInvalidMaxLeverage();
        }

        s._maxLeverage = newMaxLeverage;
        emit IUsdnProtocolEvents.MaxLeverageUpdated(newMaxLeverage);
    }

    /// @notice See {IUsdnProtocol}
    function setValidationDeadline(Storage storage s, uint256 newValidationDeadline) external {
        if (newValidationDeadline < 60) {
            revert IUsdnProtocolErrors.UsdnProtocolInvalidValidationDeadline();
        }

        if (newValidationDeadline > 1 days) {
            revert IUsdnProtocolErrors.UsdnProtocolInvalidValidationDeadline();
        }

        s._validationDeadline = newValidationDeadline;
        emit IUsdnProtocolEvents.ValidationDeadlineUpdated(newValidationDeadline);
    }

    /// @notice See {IUsdnProtocol}
    function setLiquidationPenalty(Storage storage s, uint8 newLiquidationPenalty) external {
        if (newLiquidationPenalty > 15) {
            revert IUsdnProtocolErrors.UsdnProtocolInvalidLiquidationPenalty();
        }

        s._liquidationPenalty = newLiquidationPenalty;
        emit IUsdnProtocolEvents.LiquidationPenaltyUpdated(newLiquidationPenalty);
    }

    /// @notice See {IUsdnProtocol}
    function setSafetyMarginBps(Storage storage s, uint256 newSafetyMarginBps) external {
        // safetyMarginBps greater than 20%
        if (newSafetyMarginBps > 2000) {
            revert IUsdnProtocolErrors.UsdnProtocolInvalidSafetyMarginBps();
        }

        s._safetyMarginBps = newSafetyMarginBps;
        emit IUsdnProtocolEvents.SafetyMarginBpsUpdated(newSafetyMarginBps);
    }

    /// @notice See {IUsdnProtocol}
    function setLiquidationIteration(Storage storage s, uint16 newLiquidationIteration) external {
        if (newLiquidationIteration > s.MAX_LIQUIDATION_ITERATION) {
            revert IUsdnProtocolErrors.UsdnProtocolInvalidLiquidationIteration();
        }

        s._liquidationIteration = newLiquidationIteration;
        emit IUsdnProtocolEvents.LiquidationIterationUpdated(newLiquidationIteration);
    }

    /// @notice See {IUsdnProtocol}
    function setEMAPeriod(Storage storage s, uint128 newEMAPeriod) external {
        if (newEMAPeriod > 90 days) {
            revert IUsdnProtocolErrors.UsdnProtocolInvalidEMAPeriod();
        }

        s._EMAPeriod = newEMAPeriod;
        emit IUsdnProtocolEvents.EMAPeriodUpdated(newEMAPeriod);
    }

    /// @notice See {IUsdnProtocol}
    function setFundingSF(Storage storage s, uint256 newFundingSF) external {
        if (newFundingSF > 10 ** s.FUNDING_SF_DECIMALS) {
            revert IUsdnProtocolErrors.UsdnProtocolInvalidFundingSF();
        }

        s._fundingSF = newFundingSF;
        emit IUsdnProtocolEvents.FundingSFUpdated(newFundingSF);
    }

    /// @notice See {IUsdnProtocol}
    function setProtocolFeeBps(Storage storage s, uint16 newProtocolFeeBps) external {
        if (newProtocolFeeBps > s.BPS_DIVISOR) {
            revert IUsdnProtocolErrors.UsdnProtocolInvalidProtocolFeeBps();
        }
        s._protocolFeeBps = newProtocolFeeBps;
        emit IUsdnProtocolEvents.FeeBpsUpdated(newProtocolFeeBps);
    }

    /// @notice See {IUsdnProtocol}
    function setPositionFeeBps(Storage storage s, uint16 newPositionFee) external {
        // `newPositionFee` greater than 20%
        if (newPositionFee > 2000) {
            revert IUsdnProtocolErrors.UsdnProtocolInvalidPositionFee();
        }
        s._positionFeeBps = newPositionFee;
        emit IUsdnProtocolEvents.PositionFeeUpdated(newPositionFee);
    }

    /// @notice See {IUsdnProtocol}
    function setVaultFeeBps(Storage storage s, uint16 newVaultFee) external {
        // `newVaultFee` greater than 20%
        if (newVaultFee > 2000) {
            revert IUsdnProtocolErrors.UsdnProtocolInvalidVaultFee();
        }
        s._vaultFeeBps = newVaultFee;
        emit IUsdnProtocolEvents.VaultFeeUpdated(newVaultFee);
    }

    /// @notice See {IUsdnProtocol}
    function setRebalancerBonusBps(Storage storage s, uint16 newBonus) external {
        // `newBonus` greater than 100%
        if (newBonus > s.BPS_DIVISOR) {
            revert IUsdnProtocolErrors.UsdnProtocolInvalidRebalancerBonus();
        }
        s._rebalancerBonusBps = newBonus;
        emit IUsdnProtocolEvents.RebalancerBonusUpdated(newBonus);
    }

    /// @notice See {IUsdnProtocol}
    function setSdexBurnOnDepositRatio(Storage storage s, uint32 newRatio) external {
        // `newRatio` greater than 5%
        if (newRatio > s.SDEX_BURN_ON_DEPOSIT_DIVISOR / 20) {
            revert IUsdnProtocolErrors.UsdnProtocolInvalidBurnSdexOnDepositRatio();
        }

        s._sdexBurnOnDepositRatio = newRatio;

        emit IUsdnProtocolEvents.BurnSdexOnDepositRatioUpdated(newRatio);
    }

    /// @notice See {IUsdnProtocol}
    function setSecurityDepositValue(Storage storage s, uint64 securityDepositValue) external {
        s._securityDepositValue = securityDepositValue;
        emit IUsdnProtocolEvents.SecurityDepositValueUpdated(securityDepositValue);
    }

    /// @notice See {IUsdnProtocol}
    function setFeeThreshold(Storage storage s, uint256 newFeeThreshold) external {
        s._feeThreshold = newFeeThreshold;
        emit IUsdnProtocolEvents.FeeThresholdUpdated(newFeeThreshold);
    }

    /// @notice See {IUsdnProtocol}
    function setFeeCollector(Storage storage s, address newFeeCollector) external {
        if (newFeeCollector == address(0)) {
            revert IUsdnProtocolErrors.UsdnProtocolInvalidFeeCollector();
        }
        s._feeCollector = newFeeCollector;
        emit IUsdnProtocolEvents.FeeCollectorUpdated(newFeeCollector);
    }

    /// @notice See {IUsdnProtocol}
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

        emit IUsdnProtocolEvents.ImbalanceLimitsUpdated(
            newOpenLimitBps, newDepositLimitBps, newWithdrawalLimitBps, newCloseLimitBps, newLongImbalanceTargetBps
        );
    }

    /// @notice See {IUsdnProtocol}
    function setTargetUsdnPrice(Storage storage s, uint128 newPrice) external {
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

    /// @notice See {IUsdnProtocol}
    function setUsdnRebaseThreshold(Storage storage s, uint128 newThreshold) external {
        if (newThreshold < s._targetUsdnPrice) {
            revert IUsdnProtocolErrors.UsdnProtocolInvalidUsdnRebaseThreshold();
        }
        s._usdnRebaseThreshold = newThreshold;
        emit IUsdnProtocolEvents.UsdnRebaseThresholdUpdated(newThreshold);
    }

    /// @notice See {IUsdnProtocol}
    function setUsdnRebaseInterval(Storage storage s, uint256 newInterval) external {
        s._usdnRebaseInterval = newInterval;
        emit IUsdnProtocolEvents.UsdnRebaseIntervalUpdated(newInterval);
    }

    /// @notice See {IUsdnProtocol}
    function setMinLongPosition(Storage storage s, uint256 newMinLongPosition) external {
        s._minLongPosition = newMinLongPosition;
        emit IUsdnProtocolEvents.MinLongPositionUpdated(newMinLongPosition);

        IBaseRebalancer rebalancer = s._rebalancer;
        if (address(rebalancer) != address(0) && rebalancer.getMinAssetDeposit() < newMinLongPosition) {
            rebalancer.setMinAssetDeposit(newMinLongPosition);
        }
    }
}

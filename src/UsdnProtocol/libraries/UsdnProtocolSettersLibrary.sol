// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import { IBaseLiquidationRewardsManager } from
    "../../interfaces/LiquidationRewardsManager/IBaseLiquidationRewardsManager.sol";
import { IBaseOracleMiddleware } from "../../interfaces/OracleMiddleware/IBaseOracleMiddleware.sol";
import { IBaseRebalancer } from "../../interfaces/Rebalancer/IBaseRebalancer.sol";
import { IUsdnProtocolErrors } from "../../interfaces/UsdnProtocol/IUsdnProtocolErrors.sol";
import { IUsdnProtocolEvents } from "../../interfaces/UsdnProtocol/IUsdnProtocolEvents.sol";
import { IUsdnProtocolFallback } from "../../interfaces/UsdnProtocol/IUsdnProtocolFallback.sol";
import { IUsdnProtocolTypes as Types } from "../../interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import { UsdnProtocolConstantsLibrary as Constants } from "./UsdnProtocolConstantsLibrary.sol";
import { UsdnProtocolUtilsLibrary as Utils } from "./UsdnProtocolUtilsLibrary.sol";

library UsdnProtocolSettersLibrary {
    using SafeCast for uint256;

    /* -------------------------------------------------------------------------- */
    /*                              SET_EXTERNAL_ROLE                             */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice See
     * [IUsdnProtocolFallback](../../UsdnProtocolFallback.sol/contract.UsdnProtocolFallback.html?#setoraclemiddleware).
     */
    function setOracleMiddleware(IBaseOracleMiddleware newOracleMiddleware) external {
        Types.Storage storage s = Utils._getMainStorage();

        if (address(newOracleMiddleware) == address(0)) {
            revert IUsdnProtocolErrors.UsdnProtocolInvalidMiddlewareAddress();
        }
        if (newOracleMiddleware.getLowLatencyDelay() < s._lowLatencyValidatorDeadline) {
            revert IUsdnProtocolErrors.UsdnProtocolInvalidMiddlewareLowLatencyDelay();
        }

        s._oracleMiddleware = newOracleMiddleware;
        emit IUsdnProtocolEvents.OracleMiddlewareUpdated(address(newOracleMiddleware));
    }

    /**
     * @notice See
     * [IUsdnProtocolFallback](../../UsdnProtocolFallback.sol/contract.UsdnProtocolFallback.html?#setliquidationrewardsmanager).
     */
    function setLiquidationRewardsManager(IBaseLiquidationRewardsManager newLiquidationRewardsManager) external {
        Types.Storage storage s = Utils._getMainStorage();

        if (address(newLiquidationRewardsManager) == address(0)) {
            revert IUsdnProtocolErrors.UsdnProtocolInvalidLiquidationRewardsManagerAddress();
        }

        s._liquidationRewardsManager = newLiquidationRewardsManager;

        emit IUsdnProtocolEvents.LiquidationRewardsManagerUpdated(address(newLiquidationRewardsManager));
    }

    /**
     * @notice See
     * [IUsdnProtocolFallback](../../UsdnProtocolFallback.sol/contract.UsdnProtocolFallback.html?#setrebalancer).
     */
    function setRebalancer(IBaseRebalancer newRebalancer) external {
        Types.Storage storage s = Utils._getMainStorage();

        if (address(newRebalancer) != address(0) && s._minLongPosition > newRebalancer.getMinAssetDeposit()) {
            revert IUsdnProtocolErrors.UsdnProtocolInvalidRebalancerMinAssetDeposit();
        }

        s._rebalancer = newRebalancer;
        s._isRebalancer[address(newRebalancer)] = true;

        emit IUsdnProtocolEvents.RebalancerUpdated(address(newRebalancer));
    }

    /**
     * @notice See
     * [IUsdnProtocolFallback](../../UsdnProtocolFallback.sol/contract.UsdnProtocolFallback.html?#setfeecollector).
     */
    function setFeeCollector(address newFeeCollector) external {
        Types.Storage storage s = Utils._getMainStorage();

        if (newFeeCollector == address(0)) {
            revert IUsdnProtocolErrors.UsdnProtocolInvalidFeeCollector();
        }
        s._feeCollector = newFeeCollector;
        emit IUsdnProtocolEvents.FeeCollectorUpdated(newFeeCollector);
    }

    /* -------------------------------------------------------------------------- */
    /*                           CRITICAL_FUNCTIONS_ROLE                          */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice See
     * [IUsdnProtocolFallback](../../UsdnProtocolFallback.sol/contract.UsdnProtocolFallback.html?#setvalidatordeadlines).
     */
    function setValidatorDeadlines(uint128 newLowLatencyValidatorDeadline, uint128 newOnChainValidatorDeadline)
        external
    {
        Types.Storage storage s = Utils._getMainStorage();

        uint16 lowLatencyDelay = s._oracleMiddleware.getLowLatencyDelay();

        if (newLowLatencyValidatorDeadline < Constants.MIN_VALIDATION_DEADLINE) {
            revert IUsdnProtocolErrors.UsdnProtocolInvalidValidatorDeadline();
        }
        if (newLowLatencyValidatorDeadline > lowLatencyDelay) {
            revert IUsdnProtocolErrors.UsdnProtocolInvalidValidatorDeadline();
        }
        if (newOnChainValidatorDeadline > Constants.MAX_VALIDATION_DEADLINE) {
            revert IUsdnProtocolErrors.UsdnProtocolInvalidValidatorDeadline();
        }

        s._lowLatencyValidatorDeadline = newLowLatencyValidatorDeadline;
        s._onChainValidatorDeadline = newOnChainValidatorDeadline;
        emit IUsdnProtocolEvents.ValidatorDeadlinesUpdated(newLowLatencyValidatorDeadline, newOnChainValidatorDeadline);
    }

    /* -------------------------------------------------------------------------- */
    /*                          SET_PROTOCOL_PARAMS_ROLE                          */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice See
     * [IUsdnProtocolFallback](../../UsdnProtocolFallback.sol/contract.UsdnProtocolFallback.html?#setminleverage).
     */
    function setMinLeverage(uint256 newMinLeverage) external {
        Types.Storage storage s = Utils._getMainStorage();

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

    /**
     * @notice See
     * [IUsdnProtocolFallback](../../UsdnProtocolFallback.sol/contract.UsdnProtocolFallback.html?#setmaxleverage).
     */
    function setMaxLeverage(uint256 newMaxLeverage) external {
        Types.Storage storage s = Utils._getMainStorage();

        if (newMaxLeverage <= s._minLeverage) {
            revert IUsdnProtocolErrors.UsdnProtocolInvalidMaxLeverage();
        }

        // `maxLeverage` greater than 100
        if (newMaxLeverage > Constants.MAX_LEVERAGE) {
            revert IUsdnProtocolErrors.UsdnProtocolInvalidMaxLeverage();
        }

        s._maxLeverage = newMaxLeverage;
        emit IUsdnProtocolEvents.MaxLeverageUpdated(newMaxLeverage);
    }

    /**
     * @notice See
     * [IUsdnProtocolFallback](../../UsdnProtocolFallback.sol/contract.UsdnProtocolFallback.html?#setliquidationpenalty).
     */
    function setLiquidationPenalty(uint24 newLiquidationPenalty) external {
        Types.Storage storage s = Utils._getMainStorage();

        if (newLiquidationPenalty > Constants.MAX_LIQUIDATION_PENALTY) {
            revert IUsdnProtocolErrors.UsdnProtocolInvalidLiquidationPenalty();
        }

        s._liquidationPenalty = newLiquidationPenalty;
        emit IUsdnProtocolEvents.LiquidationPenaltyUpdated(newLiquidationPenalty);
    }

    /**
     * @notice See
     * [IUsdnProtocolFallback](../../UsdnProtocolFallback.sol/contract.UsdnProtocolFallback.html?#setemaperiod).
     */
    function setEMAPeriod(uint128 newEMAPeriod) external {
        Types.Storage storage s = Utils._getMainStorage();

        if (newEMAPeriod > Constants.MAX_EMA_PERIOD) {
            revert IUsdnProtocolErrors.UsdnProtocolInvalidEMAPeriod();
        }

        s._EMAPeriod = newEMAPeriod;
        emit IUsdnProtocolEvents.EMAPeriodUpdated(newEMAPeriod);
    }

    /**
     * @notice See
     * [IUsdnProtocolFallback](../../UsdnProtocolFallback.sol/contract.UsdnProtocolFallback.html?#setfundingsf).
     */
    function setFundingSF(uint256 newFundingSF) external {
        Types.Storage storage s = Utils._getMainStorage();

        if (newFundingSF > 10 ** Constants.FUNDING_SF_DECIMALS) {
            revert IUsdnProtocolErrors.UsdnProtocolInvalidFundingSF();
        }

        s._fundingSF = newFundingSF;
        emit IUsdnProtocolEvents.FundingSFUpdated(newFundingSF);
    }

    /**
     * @notice See
     * [IUsdnProtocolFallback](../../UsdnProtocolFallback.sol/contract.UsdnProtocolFallback.html?#setprotocolfeebps).
     */
    function setProtocolFeeBps(uint16 newProtocolFeeBps) external {
        Types.Storage storage s = Utils._getMainStorage();

        if (newProtocolFeeBps > Constants.MAX_PROTOCOL_FEE_BPS) {
            revert IUsdnProtocolErrors.UsdnProtocolInvalidProtocolFeeBps();
        }
        s._protocolFeeBps = newProtocolFeeBps;
        emit IUsdnProtocolEvents.FeeBpsUpdated(newProtocolFeeBps);
    }

    /**
     * @notice See
     * [IUsdnProtocolFallback](../../UsdnProtocolFallback.sol/contract.UsdnProtocolFallback.html?#setpositionfeebps).
     */
    function setPositionFeeBps(uint16 newPositionFee) external {
        Types.Storage storage s = Utils._getMainStorage();

        // `newPositionFee` greater than 20%
        if (newPositionFee > Constants.MAX_POSITION_FEE_BPS) {
            revert IUsdnProtocolErrors.UsdnProtocolInvalidPositionFee();
        }
        s._positionFeeBps = newPositionFee;
        emit IUsdnProtocolEvents.PositionFeeUpdated(newPositionFee);
    }

    /**
     * @notice See
     * [IUsdnProtocolFallback](../../UsdnProtocolFallback.sol/contract.UsdnProtocolFallback.html?#setvaultfeebps).
     */
    function setVaultFeeBps(uint16 newVaultFee) external {
        Types.Storage storage s = Utils._getMainStorage();

        // `newVaultFee` greater than 20%
        if (newVaultFee > Constants.MAX_VAULT_FEE_BPS) {
            revert IUsdnProtocolErrors.UsdnProtocolInvalidVaultFee();
        }
        s._vaultFeeBps = newVaultFee;
        emit IUsdnProtocolEvents.VaultFeeUpdated(newVaultFee);
    }

    /**
     * @notice See
     * [IUsdnProtocolFallback](../../UsdnProtocolFallback.sol/contract.UsdnProtocolFallback.html?#setrebalancerbonusbps).
     */
    function setRebalancerBonusBps(uint16 newBonus) external {
        Types.Storage storage s = Utils._getMainStorage();

        // `newBonus` greater than 100%
        if (newBonus > Constants.BPS_DIVISOR) {
            revert IUsdnProtocolErrors.UsdnProtocolInvalidRebalancerBonus();
        }
        s._rebalancerBonusBps = newBonus;
        emit IUsdnProtocolEvents.RebalancerBonusUpdated(newBonus);
    }

    /**
     * @notice See
     * [IUsdnProtocolFallback](../../UsdnProtocolFallback.sol/contract.UsdnProtocolFallback.html?#setsdexburnondepositratio).
     */
    function setSdexBurnOnDepositRatio(uint32 newRatio) external {
        Types.Storage storage s = Utils._getMainStorage();

        // `newRatio` greater than 5%
        if (newRatio > Constants.SDEX_BURN_ON_DEPOSIT_DIVISOR / 20) {
            revert IUsdnProtocolErrors.UsdnProtocolInvalidBurnSdexOnDepositRatio();
        }

        s._sdexBurnOnDepositRatio = newRatio;

        emit IUsdnProtocolEvents.BurnSdexOnDepositRatioUpdated(newRatio);
    }

    /**
     * @notice See
     * [IUsdnProtocolFallback](../../UsdnProtocolFallback.sol/contract.UsdnProtocolFallback.html?#setsecuritydepositvalue).
     */
    function setSecurityDepositValue(uint64 securityDepositValue) external {
        Types.Storage storage s = Utils._getMainStorage();

        if (securityDepositValue > Constants.MAX_SECURITY_DEPOSIT) {
            revert IUsdnProtocolErrors.UsdnProtocolInvalidSecurityDeposit();
        }
        s._securityDepositValue = securityDepositValue;
        emit IUsdnProtocolEvents.SecurityDepositValueUpdated(securityDepositValue);
    }

    /**
     * @notice See
     * [IUsdnProtocolFallback](../../UsdnProtocolFallback.sol/contract.UsdnProtocolFallback.html?#setexpoimbalancelimits).
     */
    function setExpoImbalanceLimits(
        uint256 newOpenLimitBps,
        uint256 newDepositLimitBps,
        uint256 newWithdrawalLimitBps,
        uint256 newCloseLimitBps,
        uint256 newRebalancerCloseLimitBps,
        int256 newLongImbalanceTargetBps
    ) external {
        Types.Storage storage s = Utils._getMainStorage();

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

        if (newRebalancerCloseLimitBps != 0 && newRebalancerCloseLimitBps > newCloseLimitBps) {
            // rebalancer close limit higher than close limit not permitted
            revert IUsdnProtocolErrors.UsdnProtocolInvalidExpoImbalanceLimit();
        }
        s._rebalancerCloseExpoImbalanceLimitBps = newRebalancerCloseLimitBps.toInt256();

        // casts are safe here as values are safely casted earlier
        if (
            newLongImbalanceTargetBps > int256(newCloseLimitBps)
                || newLongImbalanceTargetBps < -int256(newWithdrawalLimitBps)
                || newLongImbalanceTargetBps < -int256(Constants.BPS_DIVISOR / 2) // the target cannot be lower than -50%
        ) {
            revert IUsdnProtocolErrors.UsdnProtocolInvalidLongImbalanceTarget();
        }

        // `newRebalancerCloseLimit` should be lower than `newLongImbalanceTarget` to prevent users from instantly
        // closing their positions. If `newRebalancerCloseLimitBps` is deactivated (set to 0),
        // `newLongImbalanceTargetBps` can take any value
        if (newRebalancerCloseLimitBps != 0 && int256(newRebalancerCloseLimitBps) >= newLongImbalanceTargetBps) {
            revert IUsdnProtocolErrors.UsdnProtocolInvalidLongImbalanceTarget();
        }

        s._longImbalanceTargetBps = newLongImbalanceTargetBps;

        emit IUsdnProtocolEvents.ImbalanceLimitsUpdated(
            newOpenLimitBps,
            newDepositLimitBps,
            newWithdrawalLimitBps,
            newCloseLimitBps,
            newRebalancerCloseLimitBps,
            newLongImbalanceTargetBps
        );
    }

    /**
     * @notice See
     * [IUsdnProtocolFallback](../../UsdnProtocolFallback.sol/contract.UsdnProtocolFallback.html?#setminlongposition).
     */
    function setMinLongPosition(uint256 newMinLongPosition) external {
        Types.Storage storage s = Utils._getMainStorage();

        if (newMinLongPosition > Constants.MAX_MIN_LONG_POSITION) {
            revert IUsdnProtocolErrors.UsdnProtocolInvalidMinLongPosition();
        }
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

    /**
     * @notice See
     * [IUsdnProtocolFallback](../../UsdnProtocolFallback.sol/contract.UsdnProtocolFallback.html?#setsafetymarginbps).
     */
    function setSafetyMarginBps(uint256 newSafetyMarginBps) external {
        Types.Storage storage s = Utils._getMainStorage();

        // safetyMarginBps greater than 20%
        if (newSafetyMarginBps > Constants.MAX_SAFETY_MARGIN_BPS) {
            revert IUsdnProtocolErrors.UsdnProtocolInvalidSafetyMarginBps();
        }

        s._safetyMarginBps = newSafetyMarginBps;
        emit IUsdnProtocolEvents.SafetyMarginBpsUpdated(newSafetyMarginBps);
    }

    /**
     * @notice See
     * [IUsdnProtocolFallback](../../UsdnProtocolFallback.sol/contract.UsdnProtocolFallback.html?#setliquidationiteration).
     */
    function setLiquidationIteration(uint16 newLiquidationIteration) external {
        Types.Storage storage s = Utils._getMainStorage();

        if (newLiquidationIteration > Constants.MAX_LIQUIDATION_ITERATION) {
            revert IUsdnProtocolErrors.UsdnProtocolInvalidLiquidationIteration();
        }

        s._liquidationIteration = newLiquidationIteration;
        emit IUsdnProtocolEvents.LiquidationIterationUpdated(newLiquidationIteration);
    }

    /**
     * @notice See
     * [IUsdnProtocolFallback](../../UsdnProtocolFallback.sol/contract.UsdnProtocolFallback.html?#setfeethreshold).
     */
    function setFeeThreshold(uint256 newFeeThreshold) external {
        Types.Storage storage s = Utils._getMainStorage();

        s._feeThreshold = newFeeThreshold;
        emit IUsdnProtocolEvents.FeeThresholdUpdated(newFeeThreshold);
    }

    /* -------------------------------------------------------------------------- */
    /*                            SET_USDN_PARAMS_ROLE                            */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice See
     * [IUsdnProtocolFallback](../../UsdnProtocolFallback.sol/contract.UsdnProtocolFallback.html?#settargetusdnprice).
     */
    function setTargetUsdnPrice(uint128 newPrice) external {
        Types.Storage storage s = Utils._getMainStorage();

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

    /**
     * @notice See
     * [IUsdnProtocolFallback](../../UsdnProtocolFallback.sol/contract.UsdnProtocolFallback.html?#setusdnrebasethreshold).
     */
    function setUsdnRebaseThreshold(uint128 newThreshold) external {
        Types.Storage storage s = Utils._getMainStorage();

        if (newThreshold < s._targetUsdnPrice) {
            revert IUsdnProtocolErrors.UsdnProtocolInvalidUsdnRebaseThreshold();
        }
        if (newThreshold > uint128(2 * 10 ** s._priceFeedDecimals)) {
            // values greater than $2 are not allowed
            revert IUsdnProtocolErrors.UsdnProtocolInvalidUsdnRebaseThreshold();
        }
        s._usdnRebaseThreshold = newThreshold;
        emit IUsdnProtocolEvents.UsdnRebaseThresholdUpdated(newThreshold);
    }
}

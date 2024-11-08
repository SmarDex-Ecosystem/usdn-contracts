// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import { AccessControlDefaultAdminRulesUpgradeable } from
    "@openzeppelin/contracts-upgradeable/access/extensions/AccessControlDefaultAdminRulesUpgradeable.sol";
import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { FixedPointMathLib } from "solady/src/utils/FixedPointMathLib.sol";

import { IBaseLiquidationRewardsManager } from
    "../interfaces/LiquidationRewardsManager/IBaseLiquidationRewardsManager.sol";
import { IBaseOracleMiddleware } from "../interfaces/OracleMiddleware/IBaseOracleMiddleware.sol";
import { IBaseRebalancer } from "../interfaces/Rebalancer/IBaseRebalancer.sol";
import { IUsdn } from "../interfaces/Usdn/IUsdn.sol";
import { IUsdnProtocolEvents } from "../interfaces/UsdnProtocol/IUsdnProtocolEvents.sol";
import { IUsdnProtocolFallback } from "../interfaces/UsdnProtocol/IUsdnProtocolFallback.sol";
import { IUsdnProtocolTypes as Types } from "../interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import { HugeUint } from "../libraries/HugeUint.sol";
import { UsdnProtocolConstantsLibrary as Constants } from "./libraries/UsdnProtocolConstantsLibrary.sol";
import { UsdnProtocolCoreLibrary as Core } from "./libraries/UsdnProtocolCoreLibrary.sol";
import { UsdnProtocolLongLibrary as Long } from "./libraries/UsdnProtocolLongLibrary.sol";
import { UsdnProtocolUtilsLibrary as Utils } from "./libraries/UsdnProtocolUtilsLibrary.sol";
import { UsdnProtocolVaultLibrary as Vault } from "./libraries/UsdnProtocolVaultLibrary.sol";

contract UsdnProtocolFallback is
    IUsdnProtocolFallback,
    PausableUpgradeable,
    AccessControlDefaultAdminRulesUpgradeable
{
    using SafeCast for uint256;

    /// @inheritdoc IUsdnProtocolFallback
    function getEffectivePriceForTick(int24 tick) external view returns (uint128 price_) {
        return Utils.getEffectivePriceForTick(tick);
    }

    /// @inheritdoc IUsdnProtocolFallback
    function getEffectivePriceForTick(
        int24 tick,
        uint256 assetPrice,
        uint256 longTradingExpo,
        HugeUint.Uint512 memory accumulator
    ) external pure returns (uint128 price_) {
        return Utils.getEffectivePriceForTick(tick, assetPrice, longTradingExpo, accumulator);
    }

    /// @inheritdoc IUsdnProtocolFallback
    function previewDeposit(uint256 amount, uint128 price, uint128 timestamp)
        external
        view
        returns (uint256 usdnSharesExpected_, uint256 sdexToBurn_)
    {
        Types.Storage storage s = Utils._getMainStorage();

        uint256 vaultBalance = Vault.vaultAssetAvailableWithFunding(price, timestamp);
        if (vaultBalance == 0) {
            revert UsdnProtocolEmptyVault();
        }
        IUsdn usdn = s._usdn;
        uint256 fees = FixedPointMathLib.fullMulDiv(amount, s._vaultFeeBps, Constants.BPS_DIVISOR);
        uint256 amountAfterFees = amount - fees;
        usdnSharesExpected_ = Utils._calcMintUsdnShares(amountAfterFees, vaultBalance + fees, usdn.totalShares());
        sdexToBurn_ = Utils._calcSdexToBurn(usdn.convertToTokens(usdnSharesExpected_), s._sdexBurnOnDepositRatio);
    }

    /// @inheritdoc IUsdnProtocolFallback
    function previewWithdraw(uint256 usdnShares, uint128 price, uint128 timestamp)
        external
        view
        returns (uint256 assetExpected_)
    {
        Types.Storage storage s = Utils._getMainStorage();

        uint256 available = Vault.vaultAssetAvailableWithFunding(price, timestamp);
        assetExpected_ = Utils._calcBurnUsdn(usdnShares, available, s._usdn.totalShares(), s._vaultFeeBps);
    }

    /// @inheritdoc IUsdnProtocolFallback
    function refundSecurityDeposit(address payable validator) external whenNotPaused {
        uint256 securityDepositValue = Core._removeStalePendingAction(validator);
        if (securityDepositValue > 0) {
            Utils._refundEther(securityDepositValue, validator);
        } else {
            revert UsdnProtocolNotEligibleForRefund(validator);
        }
    }

    /// @inheritdoc IUsdnProtocolFallback
    function removeBlockedPendingAction(address validator, address payable to)
        external
        onlyRole(Constants.CRITICAL_FUNCTIONS_ROLE)
    {
        Core.removeBlockedPendingAction(validator, to);
    }

    /// @inheritdoc IUsdnProtocolFallback
    function removeBlockedPendingActionNoCleanup(address validator, address payable to)
        external
        onlyRole(Constants.CRITICAL_FUNCTIONS_ROLE)
    {
        Core.removeBlockedPendingActionNoCleanup(validator, to);
    }

    /// @inheritdoc IUsdnProtocolFallback
    function removeBlockedPendingAction(uint128 rawIndex, address payable to)
        external
        onlyRole(Constants.CRITICAL_FUNCTIONS_ROLE)
    {
        Core._removeBlockedPendingAction(rawIndex, to, true);
    }

    /// @inheritdoc IUsdnProtocolFallback
    function removeBlockedPendingActionNoCleanup(uint128 rawIndex, address payable to)
        external
        onlyRole(Constants.CRITICAL_FUNCTIONS_ROLE)
    {
        Core._removeBlockedPendingAction(rawIndex, to, false);
    }

    /// @inheritdoc IUsdnProtocolFallback
    function LEVERAGE_DECIMALS() external pure returns (uint8) {
        return Constants.LEVERAGE_DECIMALS;
    }

    /// @inheritdoc IUsdnProtocolFallback
    function FUNDING_RATE_DECIMALS() external pure returns (uint8) {
        return Constants.FUNDING_RATE_DECIMALS;
    }

    /// @inheritdoc IUsdnProtocolFallback
    function REBALANCER_MIN_LEVERAGE() external pure returns (uint256) {
        return Constants.REBALANCER_MIN_LEVERAGE;
    }

    /// @inheritdoc IUsdnProtocolFallback
    function TOKENS_DECIMALS() external pure returns (uint8) {
        return Constants.TOKENS_DECIMALS;
    }

    /// @inheritdoc IUsdnProtocolFallback
    function LIQUIDATION_MULTIPLIER_DECIMALS() external pure returns (uint8) {
        return Constants.LIQUIDATION_MULTIPLIER_DECIMALS;
    }

    /// @inheritdoc IUsdnProtocolFallback
    function FUNDING_SF_DECIMALS() external pure returns (uint8) {
        return Constants.FUNDING_SF_DECIMALS;
    }

    /// @inheritdoc IUsdnProtocolFallback
    function SDEX_BURN_ON_DEPOSIT_DIVISOR() external pure returns (uint256) {
        return Constants.SDEX_BURN_ON_DEPOSIT_DIVISOR;
    }

    /// @inheritdoc IUsdnProtocolFallback
    function BPS_DIVISOR() external pure returns (uint256) {
        return Constants.BPS_DIVISOR;
    }

    /// @inheritdoc IUsdnProtocolFallback
    function MAX_LIQUIDATION_ITERATION() external pure returns (uint16) {
        return Constants.MAX_LIQUIDATION_ITERATION;
    }

    /// @inheritdoc IUsdnProtocolFallback
    function NO_POSITION_TICK() external pure returns (int24) {
        return Constants.NO_POSITION_TICK;
    }

    /// @inheritdoc IUsdnProtocolFallback
    function DEAD_ADDRESS() external pure returns (address) {
        return Constants.DEAD_ADDRESS;
    }

    /// @inheritdoc IUsdnProtocolFallback
    function MIN_USDN_SUPPLY() external pure returns (uint256) {
        return Constants.MIN_USDN_SUPPLY;
    }

    /// @inheritdoc IUsdnProtocolFallback
    function MAX_ACTIONABLE_PENDING_ACTIONS() external pure returns (uint256) {
        return Constants.MAX_ACTIONABLE_PENDING_ACTIONS;
    }

    /// @inheritdoc IUsdnProtocolFallback
    function MIN_LONG_TRADING_EXPO_BPS() external pure returns (uint256) {
        return Constants.MIN_LONG_TRADING_EXPO_BPS;
    }

    /// @inheritdoc IUsdnProtocolFallback
    function getTickSpacing() external view returns (int24) {
        return Utils._getMainStorage()._tickSpacing;
    }

    /// @inheritdoc IUsdnProtocolFallback
    function getAsset() external view returns (IERC20Metadata) {
        return Utils._getMainStorage()._asset;
    }

    /// @inheritdoc IUsdnProtocolFallback
    function getSdex() external view returns (IERC20Metadata) {
        return Utils._getMainStorage()._sdex;
    }

    /// @inheritdoc IUsdnProtocolFallback
    function getPriceFeedDecimals() external view returns (uint8) {
        return Utils._getMainStorage()._priceFeedDecimals;
    }

    /// @inheritdoc IUsdnProtocolFallback
    function getAssetDecimals() external view returns (uint8) {
        return Utils._getMainStorage()._assetDecimals;
    }

    /// @inheritdoc IUsdnProtocolFallback
    function getUsdn() external view returns (IUsdn) {
        return Utils._getMainStorage()._usdn;
    }

    /// @inheritdoc IUsdnProtocolFallback
    function getUsdnMinDivisor() external view returns (uint256) {
        return Utils._getMainStorage()._usdnMinDivisor;
    }

    /* -------------------------------------------------------------------------- */
    /*                                 Parameters getters                         */
    /* -------------------------------------------------------------------------- */

    /// @inheritdoc IUsdnProtocolFallback
    function getOracleMiddleware() external view returns (IBaseOracleMiddleware) {
        return Utils._getMainStorage()._oracleMiddleware;
    }

    /// @inheritdoc IUsdnProtocolFallback
    function getLiquidationRewardsManager() external view returns (IBaseLiquidationRewardsManager) {
        return Utils._getMainStorage()._liquidationRewardsManager;
    }

    /// @inheritdoc IUsdnProtocolFallback
    function getRebalancer() external view returns (IBaseRebalancer) {
        return Utils._getMainStorage()._rebalancer;
    }

    /// @inheritdoc IUsdnProtocolFallback
    function getMinLeverage() external view returns (uint256) {
        return Utils._getMainStorage()._minLeverage;
    }

    /// @inheritdoc IUsdnProtocolFallback
    function getMaxLeverage() external view returns (uint256) {
        return Utils._getMainStorage()._maxLeverage;
    }

    /// @inheritdoc IUsdnProtocolFallback
    function getLowLatencyValidatorDeadline() external view returns (uint128) {
        return Utils._getMainStorage()._lowLatencyValidatorDeadline;
    }

    /// @inheritdoc IUsdnProtocolFallback
    function getOnChainValidatorDeadline() external view returns (uint128) {
        return Utils._getMainStorage()._onChainValidatorDeadline;
    }

    /// @inheritdoc IUsdnProtocolFallback
    function getLiquidationPenalty() external view returns (uint24) {
        return Utils._getMainStorage()._liquidationPenalty;
    }

    /// @inheritdoc IUsdnProtocolFallback
    function getSafetyMarginBps() external view returns (uint256) {
        return Utils._getMainStorage()._safetyMarginBps;
    }

    /// @inheritdoc IUsdnProtocolFallback
    function getLiquidationIteration() external view returns (uint16) {
        return Utils._getMainStorage()._liquidationIteration;
    }

    /// @inheritdoc IUsdnProtocolFallback
    function getEMAPeriod() external view returns (uint128) {
        return Utils._getMainStorage()._EMAPeriod;
    }

    /// @inheritdoc IUsdnProtocolFallback
    function getFundingSF() external view returns (uint256) {
        return Utils._getMainStorage()._fundingSF;
    }

    /// @inheritdoc IUsdnProtocolFallback
    function getProtocolFeeBps() external view returns (uint16) {
        return Utils._getMainStorage()._protocolFeeBps;
    }

    /// @inheritdoc IUsdnProtocolFallback
    function getPositionFeeBps() external view returns (uint16) {
        return Utils._getMainStorage()._positionFeeBps;
    }

    /// @inheritdoc IUsdnProtocolFallback
    function getVaultFeeBps() external view returns (uint16) {
        return Utils._getMainStorage()._vaultFeeBps;
    }

    /// @inheritdoc IUsdnProtocolFallback
    function getRebalancerBonusBps() external view returns (uint16) {
        return Utils._getMainStorage()._rebalancerBonusBps;
    }

    /// @inheritdoc IUsdnProtocolFallback
    function getSdexBurnOnDepositRatio() external view returns (uint32) {
        return Utils._getMainStorage()._sdexBurnOnDepositRatio;
    }

    /// @inheritdoc IUsdnProtocolFallback
    function getSecurityDepositValue() external view returns (uint64) {
        return Utils._getMainStorage()._securityDepositValue;
    }

    /// @inheritdoc IUsdnProtocolFallback
    function getFeeThreshold() external view returns (uint256) {
        return Utils._getMainStorage()._feeThreshold;
    }

    /// @inheritdoc IUsdnProtocolFallback
    function getFeeCollector() external view returns (address) {
        return Utils._getMainStorage()._feeCollector;
    }

    /// @inheritdoc IUsdnProtocolFallback
    function getMiddlewareValidationDelay() external view returns (uint256) {
        return Utils._getMainStorage()._oracleMiddleware.getValidationDelay();
    }

    /// @inheritdoc IUsdnProtocolFallback
    function getTargetUsdnPrice() external view returns (uint128) {
        return Utils._getMainStorage()._targetUsdnPrice;
    }

    /// @inheritdoc IUsdnProtocolFallback
    function getUsdnRebaseThreshold() external view returns (uint128) {
        return Utils._getMainStorage()._usdnRebaseThreshold;
    }

    /// @inheritdoc IUsdnProtocolFallback
    function getMinLongPosition() external view returns (uint256) {
        return Utils._getMainStorage()._minLongPosition;
    }

    /* -------------------------------------------------------------------------- */
    /*                                    State getters                           */
    /* -------------------------------------------------------------------------- */

    /// @inheritdoc IUsdnProtocolFallback
    function getLastFundingPerDay() external view returns (int256) {
        return Utils._getMainStorage()._lastFundingPerDay;
    }

    /// @inheritdoc IUsdnProtocolFallback
    function getLastPrice() external view returns (uint128) {
        return Utils._getMainStorage()._lastPrice;
    }

    /// @inheritdoc IUsdnProtocolFallback
    function getLastUpdateTimestamp() external view returns (uint128) {
        return Utils._getMainStorage()._lastUpdateTimestamp;
    }

    /// @inheritdoc IUsdnProtocolFallback
    function getPendingProtocolFee() external view returns (uint256) {
        return Utils._getMainStorage()._pendingProtocolFee;
    }

    /// @inheritdoc IUsdnProtocolFallback
    function getBalanceVault() external view returns (uint256) {
        return Utils._getMainStorage()._balanceVault;
    }

    /// @inheritdoc IUsdnProtocolFallback
    function getPendingBalanceVault() external view returns (int256) {
        return Utils._getMainStorage()._pendingBalanceVault;
    }

    /// @inheritdoc IUsdnProtocolFallback
    function getEMA() external view returns (int256) {
        return Utils._getMainStorage()._EMA;
    }

    /// @inheritdoc IUsdnProtocolFallback
    function getBalanceLong() external view returns (uint256) {
        return Utils._getMainStorage()._balanceLong;
    }

    /// @inheritdoc IUsdnProtocolFallback
    function getTotalExpo() external view returns (uint256) {
        return Utils._getMainStorage()._totalExpo;
    }

    /// @inheritdoc IUsdnProtocolFallback
    function getLiqMultiplierAccumulator() external view returns (HugeUint.Uint512 memory) {
        return Utils._getMainStorage()._liqMultiplierAccumulator;
    }

    /// @inheritdoc IUsdnProtocolFallback
    function getTickVersion(int24 tick) external view returns (uint256) {
        return Utils._getMainStorage()._tickVersion[tick];
    }

    /// @inheritdoc IUsdnProtocolFallback
    function getTickData(int24 tick) external view returns (Types.TickData memory) {
        Types.Storage storage s = Utils._getMainStorage();

        bytes32 cachedTickHash = Utils.tickHash(tick, s._tickVersion[tick]);
        return Utils._getMainStorage()._tickData[cachedTickHash];
    }

    /// @inheritdoc IUsdnProtocolFallback
    function getCurrentLongPosition(int24 tick, uint256 index) external view returns (Types.Position memory) {
        Types.Storage storage s = Utils._getMainStorage();

        uint256 version = s._tickVersion[tick];
        bytes32 cachedTickHash = Utils.tickHash(tick, version);
        return Utils._getMainStorage()._longPositions[cachedTickHash][index];
    }

    /// @inheritdoc IUsdnProtocolFallback
    function getHighestPopulatedTick() external view returns (int24) {
        return Utils._getMainStorage()._highestPopulatedTick;
    }

    /// @inheritdoc IUsdnProtocolFallback
    function getTotalLongPositions() external view returns (uint256) {
        return Utils._getMainStorage()._totalLongPositions;
    }

    /// @inheritdoc IUsdnProtocolFallback
    function getDepositExpoImbalanceLimitBps() external view returns (int256 depositExpoImbalanceLimitBps_) {
        Types.Storage storage s = Utils._getMainStorage();

        depositExpoImbalanceLimitBps_ = s._depositExpoImbalanceLimitBps;
    }

    /// @inheritdoc IUsdnProtocolFallback
    function getWithdrawalExpoImbalanceLimitBps() external view returns (int256 withdrawalExpoImbalanceLimitBps_) {
        Types.Storage storage s = Utils._getMainStorage();

        withdrawalExpoImbalanceLimitBps_ = s._withdrawalExpoImbalanceLimitBps;
    }

    /// @inheritdoc IUsdnProtocolFallback
    function getOpenExpoImbalanceLimitBps() external view returns (int256 openExpoImbalanceLimitBps_) {
        Types.Storage storage s = Utils._getMainStorage();

        openExpoImbalanceLimitBps_ = s._openExpoImbalanceLimitBps;
    }

    /// @inheritdoc IUsdnProtocolFallback
    function getCloseExpoImbalanceLimitBps() external view returns (int256 closeExpoImbalanceLimitBps_) {
        Types.Storage storage s = Utils._getMainStorage();

        closeExpoImbalanceLimitBps_ = s._closeExpoImbalanceLimitBps;
    }

    /// @inheritdoc IUsdnProtocolFallback
    function getRebalancerCloseExpoImbalanceLimitBps()
        external
        view
        returns (int256 rebalancerCloseExpoImbalanceLimitBps_)
    {
        Types.Storage storage s = Utils._getMainStorage();

        rebalancerCloseExpoImbalanceLimitBps_ = s._rebalancerCloseExpoImbalanceLimitBps;
    }

    /// @inheritdoc IUsdnProtocolFallback
    function getLongImbalanceTargetBps() external view returns (int256 longImbalanceTargetBps_) {
        Types.Storage storage s = Utils._getMainStorage();

        longImbalanceTargetBps_ = s._longImbalanceTargetBps;
    }

    /// @inheritdoc IUsdnProtocolFallback
    function getFallbackAddress() external view returns (address) {
        return Utils._getMainStorage()._protocolFallbackAddr;
    }

    /// @inheritdoc IUsdnProtocolFallback
    function isPaused() external view returns (bool) {
        return paused();
    }

    /// @inheritdoc IUsdnProtocolFallback
    function getNonce(address owner) external view returns (uint256) {
        return Utils._getMainStorage()._nonce[owner];
    }

    /// @inheritdoc IUsdnProtocolFallback
    function getInitiateCloseTypehash() external pure returns (bytes32) {
        return Constants.INITIATE_CLOSE_TYPEHASH;
    }

    /* -------------------------------------------------------------------------- */
    /*                              SET_EXTERNAL_ROLE                             */
    /* -------------------------------------------------------------------------- */

    /// @inheritdoc IUsdnProtocolFallback
    function setOracleMiddleware(IBaseOracleMiddleware newOracleMiddleware)
        external
        onlyRole(Constants.SET_EXTERNAL_ROLE)
    {
        Types.Storage storage s = Utils._getMainStorage();

        if (address(newOracleMiddleware) == address(0)) {
            revert UsdnProtocolInvalidMiddlewareAddress();
        }
        s._oracleMiddleware = newOracleMiddleware;
        emit IUsdnProtocolEvents.OracleMiddlewareUpdated(address(newOracleMiddleware));
    }

    /// @inheritdoc IUsdnProtocolFallback
    function setLiquidationRewardsManager(IBaseLiquidationRewardsManager newLiquidationRewardsManager)
        external
        onlyRole(Constants.SET_EXTERNAL_ROLE)
    {
        Types.Storage storage s = Utils._getMainStorage();

        if (address(newLiquidationRewardsManager) == address(0)) {
            revert UsdnProtocolInvalidLiquidationRewardsManagerAddress();
        }

        s._liquidationRewardsManager = newLiquidationRewardsManager;

        emit IUsdnProtocolEvents.LiquidationRewardsManagerUpdated(address(newLiquidationRewardsManager));
    }

    /// @inheritdoc IUsdnProtocolFallback
    function setRebalancer(IBaseRebalancer newRebalancer) external onlyRole(Constants.SET_EXTERNAL_ROLE) {
        Types.Storage storage s = Utils._getMainStorage();

        s._rebalancer = newRebalancer;

        emit IUsdnProtocolEvents.RebalancerUpdated(address(newRebalancer));
    }

    /// @inheritdoc IUsdnProtocolFallback
    function setFeeCollector(address newFeeCollector) external onlyRole(Constants.SET_EXTERNAL_ROLE) {
        Types.Storage storage s = Utils._getMainStorage();

        if (newFeeCollector == address(0)) {
            revert UsdnProtocolInvalidFeeCollector();
        }
        s._feeCollector = newFeeCollector;
        emit IUsdnProtocolEvents.FeeCollectorUpdated(newFeeCollector);
    }

    /* -------------------------------------------------------------------------- */
    /*                           CRITICAL_FUNCTIONS_ROLE                          */
    /* -------------------------------------------------------------------------- */

    /// @inheritdoc IUsdnProtocolFallback
    function setValidatorDeadlines(uint128 newLowLatencyValidatorDeadline, uint128 newOnChainValidatorDeadline)
        external
        onlyRole(Constants.CRITICAL_FUNCTIONS_ROLE)
    {
        Types.Storage storage s = Utils._getMainStorage();

        uint16 lowLatencyDelay = s._oracleMiddleware.getLowLatencyDelay();

        if (newLowLatencyValidatorDeadline < Constants.MIN_VALIDATION_DEADLINE) {
            revert UsdnProtocolInvalidValidatorDeadline();
        }
        if (newLowLatencyValidatorDeadline > lowLatencyDelay) {
            revert UsdnProtocolInvalidValidatorDeadline();
        }
        if (newOnChainValidatorDeadline > Constants.MAX_VALIDATION_DEADLINE) {
            revert UsdnProtocolInvalidValidatorDeadline();
        }

        s._lowLatencyValidatorDeadline = newLowLatencyValidatorDeadline;
        s._onChainValidatorDeadline = newOnChainValidatorDeadline;
        emit IUsdnProtocolEvents.ValidatorDeadlinesUpdated(newLowLatencyValidatorDeadline, newOnChainValidatorDeadline);
    }

    /* -------------------------------------------------------------------------- */
    /*                          SET_PROTOCOL_PARAMS_ROLE                          */
    /* -------------------------------------------------------------------------- */

    /// @inheritdoc IUsdnProtocolFallback
    function setMinLeverage(uint256 newMinLeverage) external onlyRole(Constants.SET_PROTOCOL_PARAMS_ROLE) {
        Types.Storage storage s = Utils._getMainStorage();

        // zero minLeverage
        if (newMinLeverage <= 10 ** Constants.LEVERAGE_DECIMALS) {
            revert UsdnProtocolInvalidMinLeverage();
        }

        if (newMinLeverage >= s._maxLeverage) {
            revert UsdnProtocolInvalidMinLeverage();
        }

        s._minLeverage = newMinLeverage;
        emit IUsdnProtocolEvents.MinLeverageUpdated(newMinLeverage);
    }

    /// @inheritdoc IUsdnProtocolFallback
    function setMaxLeverage(uint256 newMaxLeverage) external onlyRole(Constants.SET_PROTOCOL_PARAMS_ROLE) {
        Types.Storage storage s = Utils._getMainStorage();

        if (newMaxLeverage <= s._minLeverage) {
            revert UsdnProtocolInvalidMaxLeverage();
        }

        // `maxLeverage` greater than 100
        if (newMaxLeverage > Constants.MAX_LEVERAGE) {
            revert UsdnProtocolInvalidMaxLeverage();
        }

        s._maxLeverage = newMaxLeverage;
        emit IUsdnProtocolEvents.MaxLeverageUpdated(newMaxLeverage);
    }

    /// @inheritdoc IUsdnProtocolFallback
    function setLiquidationPenalty(uint24 newLiquidationPenalty)
        external
        onlyRole(Constants.SET_PROTOCOL_PARAMS_ROLE)
    {
        Types.Storage storage s = Utils._getMainStorage();

        if (newLiquidationPenalty > Constants.MAX_LIQUIDATION_PENALTY) {
            revert UsdnProtocolInvalidLiquidationPenalty();
        }

        s._liquidationPenalty = newLiquidationPenalty;
        emit IUsdnProtocolEvents.LiquidationPenaltyUpdated(newLiquidationPenalty);
    }

    /// @inheritdoc IUsdnProtocolFallback
    function setEMAPeriod(uint128 newEMAPeriod) external onlyRole(Constants.SET_PROTOCOL_PARAMS_ROLE) {
        Types.Storage storage s = Utils._getMainStorage();

        if (newEMAPeriod > Constants.MAX_EMA_PERIOD) {
            revert UsdnProtocolInvalidEMAPeriod();
        }

        s._EMAPeriod = newEMAPeriod;
        emit IUsdnProtocolEvents.EMAPeriodUpdated(newEMAPeriod);
    }

    /// @inheritdoc IUsdnProtocolFallback
    function setFundingSF(uint256 newFundingSF) external onlyRole(Constants.SET_PROTOCOL_PARAMS_ROLE) {
        Types.Storage storage s = Utils._getMainStorage();

        if (newFundingSF > 10 ** Constants.FUNDING_SF_DECIMALS) {
            revert UsdnProtocolInvalidFundingSF();
        }

        s._fundingSF = newFundingSF;
        emit IUsdnProtocolEvents.FundingSFUpdated(newFundingSF);
    }

    /// @inheritdoc IUsdnProtocolFallback
    function setProtocolFeeBps(uint16 newProtocolFeeBps) external onlyRole(Constants.SET_PROTOCOL_PARAMS_ROLE) {
        Types.Storage storage s = Utils._getMainStorage();

        if (newProtocolFeeBps > Constants.MAX_PROTOCOL_FEE_BPS) {
            revert UsdnProtocolInvalidProtocolFeeBps();
        }
        s._protocolFeeBps = newProtocolFeeBps;
        emit IUsdnProtocolEvents.FeeBpsUpdated(newProtocolFeeBps);
    }

    /// @inheritdoc IUsdnProtocolFallback
    function setPositionFeeBps(uint16 newPositionFee) external onlyRole(Constants.SET_PROTOCOL_PARAMS_ROLE) {
        Types.Storage storage s = Utils._getMainStorage();

        // `newPositionFee` greater than 20%
        if (newPositionFee > Constants.MAX_POSITION_FEE_BPS) {
            revert UsdnProtocolInvalidPositionFee();
        }
        s._positionFeeBps = newPositionFee;
        emit IUsdnProtocolEvents.PositionFeeUpdated(newPositionFee);
    }

    /// @inheritdoc IUsdnProtocolFallback
    function setVaultFeeBps(uint16 newVaultFee) external onlyRole(Constants.SET_PROTOCOL_PARAMS_ROLE) {
        Types.Storage storage s = Utils._getMainStorage();

        // `newVaultFee` greater than 20%
        if (newVaultFee > Constants.MAX_VAULT_FEE_BPS) {
            revert UsdnProtocolInvalidVaultFee();
        }
        s._vaultFeeBps = newVaultFee;
        emit IUsdnProtocolEvents.VaultFeeUpdated(newVaultFee);
    }

    /// @inheritdoc IUsdnProtocolFallback
    function setRebalancerBonusBps(uint16 newBonus) external onlyRole(Constants.SET_PROTOCOL_PARAMS_ROLE) {
        Types.Storage storage s = Utils._getMainStorage();

        // `newBonus` greater than 100%
        if (newBonus > Constants.BPS_DIVISOR) {
            revert UsdnProtocolInvalidRebalancerBonus();
        }
        s._rebalancerBonusBps = newBonus;
        emit IUsdnProtocolEvents.RebalancerBonusUpdated(newBonus);
    }

    /// @inheritdoc IUsdnProtocolFallback
    function setSdexBurnOnDepositRatio(uint32 newRatio) external onlyRole(Constants.SET_PROTOCOL_PARAMS_ROLE) {
        Types.Storage storage s = Utils._getMainStorage();

        // `newRatio` greater than 5%
        if (newRatio > Constants.SDEX_BURN_ON_DEPOSIT_DIVISOR / 20) {
            revert UsdnProtocolInvalidBurnSdexOnDepositRatio();
        }

        s._sdexBurnOnDepositRatio = newRatio;

        emit IUsdnProtocolEvents.BurnSdexOnDepositRatioUpdated(newRatio);
    }

    /// @inheritdoc IUsdnProtocolFallback
    function setSecurityDepositValue(uint64 securityDepositValue)
        external
        onlyRole(Constants.SET_PROTOCOL_PARAMS_ROLE)
    {
        Types.Storage storage s = Utils._getMainStorage();

        if (securityDepositValue > Constants.MAX_SECURITY_DEPOSIT) {
            revert UsdnProtocolInvalidSecurityDeposit();
        }
        s._securityDepositValue = securityDepositValue;
        emit IUsdnProtocolEvents.SecurityDepositValueUpdated(securityDepositValue);
    }

    /// @inheritdoc IUsdnProtocolFallback
    function setExpoImbalanceLimits(
        uint256 newOpenLimitBps,
        uint256 newDepositLimitBps,
        uint256 newWithdrawalLimitBps,
        uint256 newCloseLimitBps,
        uint256 newRebalancerCloseLimitBps,
        int256 newLongImbalanceTargetBps
    ) external onlyRole(Constants.SET_PROTOCOL_PARAMS_ROLE) {
        Types.Storage storage s = Utils._getMainStorage();

        s._openExpoImbalanceLimitBps = newOpenLimitBps.toInt256();
        s._depositExpoImbalanceLimitBps = newDepositLimitBps.toInt256();

        if (newWithdrawalLimitBps != 0 && newWithdrawalLimitBps < newOpenLimitBps) {
            // withdrawal limit lower than open not permitted
            revert UsdnProtocolInvalidExpoImbalanceLimit();
        }
        s._withdrawalExpoImbalanceLimitBps = newWithdrawalLimitBps.toInt256();

        if (newCloseLimitBps != 0 && newCloseLimitBps < newDepositLimitBps) {
            // close limit lower than deposit not permitted
            revert UsdnProtocolInvalidExpoImbalanceLimit();
        }
        s._closeExpoImbalanceLimitBps = newCloseLimitBps.toInt256();

        if (newRebalancerCloseLimitBps != 0 && newRebalancerCloseLimitBps > newCloseLimitBps) {
            // rebalancer close limit higher than close limit not permitted
            revert UsdnProtocolInvalidExpoImbalanceLimit();
        }
        s._rebalancerCloseExpoImbalanceLimitBps = newRebalancerCloseLimitBps.toInt256();

        // casts are safe here as values are safely casted earlier
        if (
            newLongImbalanceTargetBps > int256(newCloseLimitBps)
                || newLongImbalanceTargetBps < -int256(newWithdrawalLimitBps)
                || newLongImbalanceTargetBps < -int256(Constants.BPS_DIVISOR / 2) // The target cannot be lower than -50%
        ) {
            revert UsdnProtocolInvalidLongImbalanceTarget();
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

    /// @inheritdoc IUsdnProtocolFallback
    function setMinLongPosition(uint256 newMinLongPosition) external onlyRole(Constants.SET_PROTOCOL_PARAMS_ROLE) {
        Types.Storage storage s = Utils._getMainStorage();

        if (newMinLongPosition > Constants.MAX_MIN_LONG_POSITION) {
            revert UsdnProtocolInvalidMinLongPosition();
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

    /// @inheritdoc IUsdnProtocolFallback
    function setSafetyMarginBps(uint256 newSafetyMarginBps) external onlyRole(Constants.SET_OPTIONS_ROLE) {
        Types.Storage storage s = Utils._getMainStorage();

        // safetyMarginBps greater than 20%
        if (newSafetyMarginBps > Constants.MAX_SAFETY_MARGIN_BPS) {
            revert UsdnProtocolInvalidSafetyMarginBps();
        }

        s._safetyMarginBps = newSafetyMarginBps;
        emit IUsdnProtocolEvents.SafetyMarginBpsUpdated(newSafetyMarginBps);
    }

    /// @inheritdoc IUsdnProtocolFallback
    function setLiquidationIteration(uint16 newLiquidationIteration) external onlyRole(Constants.SET_OPTIONS_ROLE) {
        Types.Storage storage s = Utils._getMainStorage();

        if (newLiquidationIteration > Constants.MAX_LIQUIDATION_ITERATION) {
            revert UsdnProtocolInvalidLiquidationIteration();
        }

        s._liquidationIteration = newLiquidationIteration;
        emit IUsdnProtocolEvents.LiquidationIterationUpdated(newLiquidationIteration);
    }

    /// @inheritdoc IUsdnProtocolFallback
    function setFeeThreshold(uint256 newFeeThreshold) external onlyRole(Constants.SET_OPTIONS_ROLE) {
        Types.Storage storage s = Utils._getMainStorage();

        s._feeThreshold = newFeeThreshold;
        emit IUsdnProtocolEvents.FeeThresholdUpdated(newFeeThreshold);
    }

    /* -------------------------------------------------------------------------- */
    /*                            SET_USDN_PARAMS_ROLE                            */
    /* -------------------------------------------------------------------------- */

    /// @inheritdoc IUsdnProtocolFallback
    function setTargetUsdnPrice(uint128 newPrice) external onlyRole(Constants.SET_USDN_PARAMS_ROLE) {
        Types.Storage storage s = Utils._getMainStorage();

        if (newPrice > s._usdnRebaseThreshold) {
            revert UsdnProtocolInvalidTargetUsdnPrice();
        }
        if (newPrice < uint128(10 ** s._priceFeedDecimals)) {
            // values smaller than $1 are not allowed
            revert UsdnProtocolInvalidTargetUsdnPrice();
        }
        s._targetUsdnPrice = newPrice;
        emit IUsdnProtocolEvents.TargetUsdnPriceUpdated(newPrice);
    }

    /// @inheritdoc IUsdnProtocolFallback
    function setUsdnRebaseThreshold(uint128 newThreshold) external onlyRole(Constants.SET_USDN_PARAMS_ROLE) {
        Types.Storage storage s = Utils._getMainStorage();

        if (newThreshold < s._targetUsdnPrice) {
            revert UsdnProtocolInvalidUsdnRebaseThreshold();
        }
        if (newThreshold > uint128(2 * 10 ** s._priceFeedDecimals)) {
            // values greater than $2 are not allowed
            revert UsdnProtocolInvalidUsdnRebaseThreshold();
        }
        s._usdnRebaseThreshold = newThreshold;
        emit IUsdnProtocolEvents.UsdnRebaseThresholdUpdated(newThreshold);
    }

    /* -------------------------------------------------------------------------- */
    /*                            PAUSER_ROLE                                     */
    /* -------------------------------------------------------------------------- */

    /// @inheritdoc IUsdnProtocolFallback
    function pause() external onlyRole(Constants.PAUSER_ROLE) {
        _pause();
    }

    /* -------------------------------------------------------------------------- */
    /*                            UNPAUSER_ROLE                                     */
    /* -------------------------------------------------------------------------- */

    /// @inheritdoc IUsdnProtocolFallback
    function unpause() external onlyRole(Constants.UNPAUSER_ROLE) {
        _unpause();
    }
}

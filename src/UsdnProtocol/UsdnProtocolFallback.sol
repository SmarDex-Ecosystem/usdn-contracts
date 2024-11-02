// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { FixedPointMathLib } from "solady/src/utils/FixedPointMathLib.sol";

import { IBaseLiquidationRewardsManager } from
    "../interfaces/LiquidationRewardsManager/IBaseLiquidationRewardsManager.sol";
import { IBaseOracleMiddleware } from "../interfaces/OracleMiddleware/IBaseOracleMiddleware.sol";
import { IBaseRebalancer } from "../interfaces/Rebalancer/IBaseRebalancer.sol";
import { IUsdn } from "../interfaces/Usdn/IUsdn.sol";
import { IUsdnProtocolErrors } from "../interfaces/UsdnProtocol/IUsdnProtocolErrors.sol";
import { IUsdnProtocolEvents } from "../interfaces/UsdnProtocol/IUsdnProtocolEvents.sol";
import { IUsdnProtocolFallback } from "../interfaces/UsdnProtocol/IUsdnProtocolFallback.sol";
import { HugeUint } from "../libraries/HugeUint.sol";
import { UsdnProtocolStorage } from "./UsdnProtocolStorage.sol";
import { UsdnProtocolConstantsLibrary as Constants } from "./libraries/UsdnProtocolConstantsLibrary.sol";
import { UsdnProtocolCoreLibrary as Core } from "./libraries/UsdnProtocolCoreLibrary.sol";
import { UsdnProtocolUtilsLibrary as Utils } from "./libraries/UsdnProtocolUtilsLibrary.sol";
import { UsdnProtocolVaultLibrary as Vault } from "./libraries/UsdnProtocolVaultLibrary.sol";

contract UsdnProtocolFallback is IUsdnProtocolFallback, UsdnProtocolStorage {
    using SafeCast for uint256;

    /// @inheritdoc IUsdnProtocolFallback
    function getEffectivePriceForTick(int24 tick) external view returns (uint128 price_) {
        return Utils.getEffectivePriceForTick(s, tick);
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
        uint256 vaultBalance = Vault.vaultAssetAvailableWithFunding(s, price, timestamp);
        if (vaultBalance == 0) {
            revert IUsdnProtocolErrors.UsdnProtocolEmptyVault();
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
        uint256 available = Vault.vaultAssetAvailableWithFunding(s, price, timestamp);
        assetExpected_ = Utils._calcBurnUsdn(usdnShares, available, s._usdn.totalShares(), s._vaultFeeBps);
    }

    /// @inheritdoc IUsdnProtocolFallback
    function refundSecurityDeposit(address payable validator) external whenNotPaused {
        uint256 securityDepositValue = Core._removeStalePendingAction(s, validator);
        if (securityDepositValue > 0) {
            Utils._refundEther(securityDepositValue, validator);
        } else {
            revert IUsdnProtocolErrors.UsdnProtocolNotEligibleForRefund(validator);
        }
    }

    /// @inheritdoc IUsdnProtocolFallback
    function removeBlockedPendingAction(address validator, address payable to)
        external
        onlyRole(CRITICAL_FUNCTIONS_ROLE)
    {
        Core.removeBlockedPendingAction(s, validator, to);
    }

    /// @inheritdoc IUsdnProtocolFallback
    function removeBlockedPendingActionNoCleanup(address validator, address payable to)
        external
        onlyRole(CRITICAL_FUNCTIONS_ROLE)
    {
        Core.removeBlockedPendingActionNoCleanup(s, validator, to);
    }

    /// @inheritdoc IUsdnProtocolFallback
    function removeBlockedPendingAction(uint128 rawIndex, address payable to)
        external
        onlyRole(CRITICAL_FUNCTIONS_ROLE)
    {
        Core._removeBlockedPendingAction(s, rawIndex, to, true);
    }

    /// @inheritdoc IUsdnProtocolFallback
    function removeBlockedPendingActionNoCleanup(uint128 rawIndex, address payable to)
        external
        onlyRole(CRITICAL_FUNCTIONS_ROLE)
    {
        Core._removeBlockedPendingAction(s, rawIndex, to, false);
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
        return s._tickSpacing;
    }

    /// @inheritdoc IUsdnProtocolFallback
    function getAsset() external view returns (IERC20Metadata) {
        return s._asset;
    }

    /// @inheritdoc IUsdnProtocolFallback
    function getSdex() external view returns (IERC20Metadata) {
        return s._sdex;
    }

    /// @inheritdoc IUsdnProtocolFallback
    function getPriceFeedDecimals() external view returns (uint8) {
        return s._priceFeedDecimals;
    }

    /// @inheritdoc IUsdnProtocolFallback
    function getAssetDecimals() external view returns (uint8) {
        return s._assetDecimals;
    }

    /// @inheritdoc IUsdnProtocolFallback
    function getUsdn() external view returns (IUsdn) {
        return s._usdn;
    }

    /// @inheritdoc IUsdnProtocolFallback
    function getUsdnMinDivisor() external view returns (uint256) {
        return s._usdnMinDivisor;
    }

    /* -------------------------------------------------------------------------- */
    /*                                 Parameters getters                         */
    /* -------------------------------------------------------------------------- */

    /// @inheritdoc IUsdnProtocolFallback
    function getOracleMiddleware() external view returns (IBaseOracleMiddleware) {
        return s._oracleMiddleware;
    }

    /// @inheritdoc IUsdnProtocolFallback
    function getLiquidationRewardsManager() external view returns (IBaseLiquidationRewardsManager) {
        return s._liquidationRewardsManager;
    }

    /// @inheritdoc IUsdnProtocolFallback
    function getRebalancer() external view returns (IBaseRebalancer) {
        return s._rebalancer;
    }

    /// @inheritdoc IUsdnProtocolFallback
    function getMinLeverage() external view returns (uint256) {
        return s._minLeverage;
    }

    /// @inheritdoc IUsdnProtocolFallback
    function getMaxLeverage() external view returns (uint256) {
        return s._maxLeverage;
    }

    /// @inheritdoc IUsdnProtocolFallback
    function getLowLatencyValidatorDeadline() external view returns (uint128) {
        return s._lowLatencyValidatorDeadline;
    }

    /// @inheritdoc IUsdnProtocolFallback
    function getOnChainValidatorDeadline() external view returns (uint128) {
        return s._onChainValidatorDeadline;
    }

    /// @inheritdoc IUsdnProtocolFallback
    function getLiquidationPenalty() external view returns (uint24) {
        return s._liquidationPenalty;
    }

    /// @inheritdoc IUsdnProtocolFallback
    function getSafetyMarginBps() external view returns (uint256) {
        return s._safetyMarginBps;
    }

    /// @inheritdoc IUsdnProtocolFallback
    function getLiquidationIteration() external view returns (uint16) {
        return s._liquidationIteration;
    }

    /// @inheritdoc IUsdnProtocolFallback
    function getEMAPeriod() external view returns (uint128) {
        return s._EMAPeriod;
    }

    /// @inheritdoc IUsdnProtocolFallback
    function getFundingSF() external view returns (uint256) {
        return s._fundingSF;
    }

    /// @inheritdoc IUsdnProtocolFallback
    function getProtocolFeeBps() external view returns (uint16) {
        return s._protocolFeeBps;
    }

    /// @inheritdoc IUsdnProtocolFallback
    function getPositionFeeBps() external view returns (uint16) {
        return s._positionFeeBps;
    }

    /// @inheritdoc IUsdnProtocolFallback
    function getVaultFeeBps() external view returns (uint16) {
        return s._vaultFeeBps;
    }

    /// @inheritdoc IUsdnProtocolFallback
    function getRebalancerBonusBps() external view returns (uint16) {
        return s._rebalancerBonusBps;
    }

    /// @inheritdoc IUsdnProtocolFallback
    function getSdexBurnOnDepositRatio() external view returns (uint32) {
        return s._sdexBurnOnDepositRatio;
    }

    /// @inheritdoc IUsdnProtocolFallback
    function getSecurityDepositValue() external view returns (uint64) {
        return s._securityDepositValue;
    }

    /// @inheritdoc IUsdnProtocolFallback
    function getFeeThreshold() external view returns (uint256) {
        return s._feeThreshold;
    }

    /// @inheritdoc IUsdnProtocolFallback
    function getFeeCollector() external view returns (address) {
        return s._feeCollector;
    }

    /// @inheritdoc IUsdnProtocolFallback
    function getMiddlewareValidationDelay() external view returns (uint256) {
        return s._oracleMiddleware.getValidationDelay();
    }

    /// @inheritdoc IUsdnProtocolFallback
    function getTargetUsdnPrice() external view returns (uint128) {
        return s._targetUsdnPrice;
    }

    /// @inheritdoc IUsdnProtocolFallback
    function getUsdnRebaseThreshold() external view returns (uint128) {
        return s._usdnRebaseThreshold;
    }

    /// @inheritdoc IUsdnProtocolFallback
    function getMinLongPosition() external view returns (uint256) {
        return s._minLongPosition;
    }

    /* -------------------------------------------------------------------------- */
    /*                                    State getters                           */
    /* -------------------------------------------------------------------------- */

    /// @inheritdoc IUsdnProtocolFallback
    function getLastFundingPerDay() external view returns (int256) {
        return s._lastFundingPerDay;
    }

    /// @inheritdoc IUsdnProtocolFallback
    function getLastPrice() external view returns (uint128) {
        return s._lastPrice;
    }

    /// @inheritdoc IUsdnProtocolFallback
    function getLastUpdateTimestamp() external view returns (uint128) {
        return s._lastUpdateTimestamp;
    }

    /// @inheritdoc IUsdnProtocolFallback
    function getPendingProtocolFee() external view returns (uint256) {
        return s._pendingProtocolFee;
    }

    /// @inheritdoc IUsdnProtocolFallback
    function getBalanceVault() external view returns (uint256) {
        return s._balanceVault;
    }

    /// @inheritdoc IUsdnProtocolFallback
    function getPendingBalanceVault() external view returns (int256) {
        return s._pendingBalanceVault;
    }

    /// @inheritdoc IUsdnProtocolFallback
    function getEMA() external view returns (int256) {
        return s._EMA;
    }

    /// @inheritdoc IUsdnProtocolFallback
    function getBalanceLong() external view returns (uint256) {
        return s._balanceLong;
    }

    /// @inheritdoc IUsdnProtocolFallback
    function getTotalExpo() external view returns (uint256) {
        return s._totalExpo;
    }

    /// @inheritdoc IUsdnProtocolFallback
    function getLiqMultiplierAccumulator() external view returns (HugeUint.Uint512 memory) {
        return s._liqMultiplierAccumulator;
    }

    /// @inheritdoc IUsdnProtocolFallback
    function getTickVersion(int24 tick) external view returns (uint256) {
        return s._tickVersion[tick];
    }

    /// @inheritdoc IUsdnProtocolFallback
    function getTickData(int24 tick) external view returns (TickData memory) {
        bytes32 cachedTickHash = Utils.tickHash(tick, s._tickVersion[tick]);
        return s._tickData[cachedTickHash];
    }

    /// @inheritdoc IUsdnProtocolFallback
    function getCurrentLongPosition(int24 tick, uint256 index) external view returns (Position memory) {
        uint256 version = s._tickVersion[tick];
        bytes32 cachedTickHash = Utils.tickHash(tick, version);
        return s._longPositions[cachedTickHash][index];
    }

    /// @inheritdoc IUsdnProtocolFallback
    function getHighestPopulatedTick() external view returns (int24) {
        return s._highestPopulatedTick;
    }

    /// @inheritdoc IUsdnProtocolFallback
    function getTotalLongPositions() external view returns (uint256) {
        return s._totalLongPositions;
    }

    /// @inheritdoc IUsdnProtocolFallback
    function getDepositExpoImbalanceLimitBps() external view returns (int256 depositExpoImbalanceLimitBps_) {
        depositExpoImbalanceLimitBps_ = s._depositExpoImbalanceLimitBps;
    }

    /// @inheritdoc IUsdnProtocolFallback
    function getWithdrawalExpoImbalanceLimitBps() external view returns (int256 withdrawalExpoImbalanceLimitBps_) {
        withdrawalExpoImbalanceLimitBps_ = s._withdrawalExpoImbalanceLimitBps;
    }

    /// @inheritdoc IUsdnProtocolFallback
    function getOpenExpoImbalanceLimitBps() external view returns (int256 openExpoImbalanceLimitBps_) {
        openExpoImbalanceLimitBps_ = s._openExpoImbalanceLimitBps;
    }

    /// @inheritdoc IUsdnProtocolFallback
    function getCloseExpoImbalanceLimitBps() external view returns (int256 closeExpoImbalanceLimitBps_) {
        closeExpoImbalanceLimitBps_ = s._closeExpoImbalanceLimitBps;
    }

    /// @inheritdoc IUsdnProtocolFallback
    function getRebalancerCloseExpoImbalanceLimitBps()
        external
        view
        returns (int256 rebalancerCloseExpoImbalanceLimitBps_)
    {
        rebalancerCloseExpoImbalanceLimitBps_ = s._rebalancerCloseExpoImbalanceLimitBps;
    }

    /// @inheritdoc IUsdnProtocolFallback
    function getLongImbalanceTargetBps() external view returns (int256 longImbalanceTargetBps_) {
        longImbalanceTargetBps_ = s._longImbalanceTargetBps;
    }

    /// @inheritdoc IUsdnProtocolFallback
    function getFallbackAddress() external view returns (address) {
        return s._protocolFallbackAddr;
    }

    /// @inheritdoc IUsdnProtocolFallback
    function isPaused() external view returns (bool) {
        return paused();
    }

    /// @inheritdoc IUsdnProtocolFallback
    function getNonce(address owner) external view returns (uint256) {
        return s._nonce[owner];
    }

    /// @inheritdoc IUsdnProtocolFallback
    function domainSeparatorV4() external view returns (bytes32) {
        return _domainSeparatorV4();
    }

    /// @inheritdoc IUsdnProtocolFallback
    function getInitiateCloseTypehash() external pure returns (bytes32) {
        return Constants.INITIATE_CLOSE_TYPEHASH;
    }

    /* -------------------------------------------------------------------------- */
    /*                              SET_EXTERNAL_ROLE                             */
    /* -------------------------------------------------------------------------- */

    /// @inheritdoc IUsdnProtocolFallback
    function setOracleMiddleware(IBaseOracleMiddleware newOracleMiddleware) external onlyRole(SET_EXTERNAL_ROLE) {
        if (address(newOracleMiddleware) == address(0)) {
            revert IUsdnProtocolErrors.UsdnProtocolInvalidMiddlewareAddress();
        }
        s._oracleMiddleware = newOracleMiddleware;
        emit IUsdnProtocolEvents.OracleMiddlewareUpdated(address(newOracleMiddleware));
    }

    /// @inheritdoc IUsdnProtocolFallback
    function setLiquidationRewardsManager(IBaseLiquidationRewardsManager newLiquidationRewardsManager)
        external
        onlyRole(SET_EXTERNAL_ROLE)
    {
        if (address(newLiquidationRewardsManager) == address(0)) {
            revert IUsdnProtocolErrors.UsdnProtocolInvalidLiquidationRewardsManagerAddress();
        }

        s._liquidationRewardsManager = newLiquidationRewardsManager;

        emit IUsdnProtocolEvents.LiquidationRewardsManagerUpdated(address(newLiquidationRewardsManager));
    }

    /// @inheritdoc IUsdnProtocolFallback
    function setRebalancer(IBaseRebalancer newRebalancer) external onlyRole(SET_EXTERNAL_ROLE) {
        s._rebalancer = newRebalancer;

        emit IUsdnProtocolEvents.RebalancerUpdated(address(newRebalancer));
    }

    /// @inheritdoc IUsdnProtocolFallback
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

    /// @inheritdoc IUsdnProtocolFallback
    function setValidatorDeadlines(uint128 newLowLatencyValidatorDeadline, uint128 newOnChainValidatorDeadline)
        external
        onlyRole(CRITICAL_FUNCTIONS_ROLE)
    {
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

    /// @inheritdoc IUsdnProtocolFallback
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

    /// @inheritdoc IUsdnProtocolFallback
    function setMaxLeverage(uint256 newMaxLeverage) external onlyRole(SET_PROTOCOL_PARAMS_ROLE) {
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

    /// @inheritdoc IUsdnProtocolFallback
    function setLiquidationPenalty(uint24 newLiquidationPenalty) external onlyRole(SET_PROTOCOL_PARAMS_ROLE) {
        if (newLiquidationPenalty > Constants.MAX_LIQUIDATION_PENALTY) {
            revert IUsdnProtocolErrors.UsdnProtocolInvalidLiquidationPenalty();
        }

        s._liquidationPenalty = newLiquidationPenalty;
        emit IUsdnProtocolEvents.LiquidationPenaltyUpdated(newLiquidationPenalty);
    }

    /// @inheritdoc IUsdnProtocolFallback
    function setEMAPeriod(uint128 newEMAPeriod) external onlyRole(SET_PROTOCOL_PARAMS_ROLE) {
        if (newEMAPeriod > Constants.MAX_EMA_PERIOD) {
            revert IUsdnProtocolErrors.UsdnProtocolInvalidEMAPeriod();
        }

        s._EMAPeriod = newEMAPeriod;
        emit IUsdnProtocolEvents.EMAPeriodUpdated(newEMAPeriod);
    }

    /// @inheritdoc IUsdnProtocolFallback
    function setFundingSF(uint256 newFundingSF) external onlyRole(SET_PROTOCOL_PARAMS_ROLE) {
        if (newFundingSF > 10 ** Constants.FUNDING_SF_DECIMALS) {
            revert IUsdnProtocolErrors.UsdnProtocolInvalidFundingSF();
        }

        s._fundingSF = newFundingSF;
        emit IUsdnProtocolEvents.FundingSFUpdated(newFundingSF);
    }

    /// @inheritdoc IUsdnProtocolFallback
    function setProtocolFeeBps(uint16 newProtocolFeeBps) external onlyRole(SET_PROTOCOL_PARAMS_ROLE) {
        if (newProtocolFeeBps > Constants.MAX_PROTOCOL_FEE_BPS) {
            revert IUsdnProtocolErrors.UsdnProtocolInvalidProtocolFeeBps();
        }
        s._protocolFeeBps = newProtocolFeeBps;
        emit IUsdnProtocolEvents.FeeBpsUpdated(newProtocolFeeBps);
    }

    /// @inheritdoc IUsdnProtocolFallback
    function setPositionFeeBps(uint16 newPositionFee) external onlyRole(SET_PROTOCOL_PARAMS_ROLE) {
        // `newPositionFee` greater than 20%
        if (newPositionFee > Constants.MAX_POSITION_FEE_BPS) {
            revert IUsdnProtocolErrors.UsdnProtocolInvalidPositionFee();
        }
        s._positionFeeBps = newPositionFee;
        emit IUsdnProtocolEvents.PositionFeeUpdated(newPositionFee);
    }

    /// @inheritdoc IUsdnProtocolFallback
    function setVaultFeeBps(uint16 newVaultFee) external onlyRole(SET_PROTOCOL_PARAMS_ROLE) {
        // `newVaultFee` greater than 20%
        if (newVaultFee > Constants.MAX_VAULT_FEE_BPS) {
            revert IUsdnProtocolErrors.UsdnProtocolInvalidVaultFee();
        }
        s._vaultFeeBps = newVaultFee;
        emit IUsdnProtocolEvents.VaultFeeUpdated(newVaultFee);
    }

    /// @inheritdoc IUsdnProtocolFallback
    function setRebalancerBonusBps(uint16 newBonus) external onlyRole(SET_PROTOCOL_PARAMS_ROLE) {
        // `newBonus` greater than 100%
        if (newBonus > Constants.BPS_DIVISOR) {
            revert IUsdnProtocolErrors.UsdnProtocolInvalidRebalancerBonus();
        }
        s._rebalancerBonusBps = newBonus;
        emit IUsdnProtocolEvents.RebalancerBonusUpdated(newBonus);
    }

    /// @inheritdoc IUsdnProtocolFallback
    function setSdexBurnOnDepositRatio(uint32 newRatio) external onlyRole(SET_PROTOCOL_PARAMS_ROLE) {
        // `newRatio` greater than 5%
        if (newRatio > Constants.SDEX_BURN_ON_DEPOSIT_DIVISOR / 20) {
            revert IUsdnProtocolErrors.UsdnProtocolInvalidBurnSdexOnDepositRatio();
        }

        s._sdexBurnOnDepositRatio = newRatio;

        emit IUsdnProtocolEvents.BurnSdexOnDepositRatioUpdated(newRatio);
    }

    /// @inheritdoc IUsdnProtocolFallback
    function setSecurityDepositValue(uint64 securityDepositValue) external onlyRole(SET_PROTOCOL_PARAMS_ROLE) {
        if (securityDepositValue > Constants.MAX_SECURITY_DEPOSIT) {
            revert IUsdnProtocolErrors.UsdnProtocolInvalidSecurityDeposit();
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

        if (newRebalancerCloseLimitBps != 0 && newRebalancerCloseLimitBps > newCloseLimitBps) {
            // rebalancer close limit higher than close limit not permitted
            revert IUsdnProtocolErrors.UsdnProtocolInvalidExpoImbalanceLimit();
        }
        s._rebalancerCloseExpoImbalanceLimitBps = newRebalancerCloseLimitBps.toInt256();

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
            newOpenLimitBps,
            newDepositLimitBps,
            newWithdrawalLimitBps,
            newCloseLimitBps,
            newRebalancerCloseLimitBps,
            newLongImbalanceTargetBps
        );
    }

    /// @inheritdoc IUsdnProtocolFallback
    function setMinLongPosition(uint256 newMinLongPosition) external onlyRole(SET_PROTOCOL_PARAMS_ROLE) {
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

    /// @inheritdoc IUsdnProtocolFallback
    function setSafetyMarginBps(uint256 newSafetyMarginBps) external onlyRole(SET_OPTIONS_ROLE) {
        // safetyMarginBps greater than 20%
        if (newSafetyMarginBps > Constants.MAX_SAFETY_MARGIN_BPS) {
            revert IUsdnProtocolErrors.UsdnProtocolInvalidSafetyMarginBps();
        }

        s._safetyMarginBps = newSafetyMarginBps;
        emit IUsdnProtocolEvents.SafetyMarginBpsUpdated(newSafetyMarginBps);
    }

    /// @inheritdoc IUsdnProtocolFallback
    function setLiquidationIteration(uint16 newLiquidationIteration) external onlyRole(SET_OPTIONS_ROLE) {
        if (newLiquidationIteration > Constants.MAX_LIQUIDATION_ITERATION) {
            revert IUsdnProtocolErrors.UsdnProtocolInvalidLiquidationIteration();
        }

        s._liquidationIteration = newLiquidationIteration;
        emit IUsdnProtocolEvents.LiquidationIterationUpdated(newLiquidationIteration);
    }

    /// @inheritdoc IUsdnProtocolFallback
    function setFeeThreshold(uint256 newFeeThreshold) external onlyRole(SET_OPTIONS_ROLE) {
        s._feeThreshold = newFeeThreshold;
        emit IUsdnProtocolEvents.FeeThresholdUpdated(newFeeThreshold);
    }

    /* -------------------------------------------------------------------------- */
    /*                            SET_USDN_PARAMS_ROLE                            */
    /* -------------------------------------------------------------------------- */

    /// @inheritdoc IUsdnProtocolFallback
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

    /// @inheritdoc IUsdnProtocolFallback
    function setUsdnRebaseThreshold(uint128 newThreshold) external onlyRole(SET_USDN_PARAMS_ROLE) {
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

    /* -------------------------------------------------------------------------- */
    /*                            PAUSER_ROLE                                     */
    /* -------------------------------------------------------------------------- */

    /// @inheritdoc IUsdnProtocolFallback
    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    /* -------------------------------------------------------------------------- */
    /*                            UNPAUSER_ROLE                                     */
    /* -------------------------------------------------------------------------- */

    /// @inheritdoc IUsdnProtocolFallback
    function unpause() external onlyRole(UNPAUSER_ROLE) {
        _unpause();
    }
}

// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import { AccessControlDefaultAdminRulesUpgradeable } from
    "@openzeppelin/contracts-upgradeable/access/extensions/AccessControlDefaultAdminRulesUpgradeable.sol";
import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { FixedPointMathLib } from "solady/src/utils/FixedPointMathLib.sol";
import { SafeTransferLib } from "solady/src/utils/SafeTransferLib.sol";

import { IBaseLiquidationRewardsManager } from
    "../interfaces/LiquidationRewardsManager/IBaseLiquidationRewardsManager.sol";
import { IBaseOracleMiddleware } from "../interfaces/OracleMiddleware/IBaseOracleMiddleware.sol";
import { IBaseRebalancer } from "../interfaces/Rebalancer/IBaseRebalancer.sol";
import { IUsdn } from "../interfaces/Usdn/IUsdn.sol";
import { IUsdnProtocolErrors } from "../interfaces/UsdnProtocol/IUsdnProtocolErrors.sol";
import { IUsdnProtocolEvents } from "../interfaces/UsdnProtocol/IUsdnProtocolEvents.sol";
import { IUsdnProtocolFallback } from "../interfaces/UsdnProtocol/IUsdnProtocolFallback.sol";
import { HugeUint } from "../libraries/HugeUint.sol";
import { InitializableReentrancyGuard } from "../utils/InitializableReentrancyGuard.sol";
import { UsdnProtocolConstantsLibrary as Constants } from "./libraries/UsdnProtocolConstantsLibrary.sol";
import { UsdnProtocolCoreLibrary as Core } from "./libraries/UsdnProtocolCoreLibrary.sol";
import { UsdnProtocolLongLibrary as Long } from "./libraries/UsdnProtocolLongLibrary.sol";
import { UsdnProtocolSettersLibrary as Setters } from "./libraries/UsdnProtocolSettersLibrary.sol";
import { UsdnProtocolUtilsLibrary as Utils } from "./libraries/UsdnProtocolUtilsLibrary.sol";
import { UsdnProtocolVaultLibrary as Vault } from "./libraries/UsdnProtocolVaultLibrary.sol";

contract UsdnProtocolFallback is
    IUsdnProtocolErrors,
    IUsdnProtocolEvents,
    IUsdnProtocolFallback,
    InitializableReentrancyGuard,
    PausableUpgradeable,
    AccessControlDefaultAdminRulesUpgradeable
{
    using SafeTransferLib for address;

    /// @inheritdoc IUsdnProtocolFallback
    function getActionablePendingActions(address currentUser, uint256 lookAhead, uint256 maxIter)
        external
        view
        returns (PendingAction[] memory actions_, uint128[] memory rawIndices_)
    {
        return Vault.getActionablePendingActions(currentUser, lookAhead, maxIter);
    }

    /// @inheritdoc IUsdnProtocolFallback
    function getUserPendingAction(address user) external view returns (PendingAction memory action_) {
        return Core.getUserPendingAction(user);
    }

    /// @inheritdoc IUsdnProtocolFallback
    function tickHash(int24 tick, uint256 version) external pure returns (bytes32 hash_) {
        return Utils._tickHash(tick, version);
    }

    /// @inheritdoc IUsdnProtocolFallback
    function getEffectivePriceForTick(int24 tick) external view returns (uint128 price_) {
        return Utils._getEffectivePriceForTick(tick);
    }

    /// @inheritdoc IUsdnProtocolFallback
    function getEffectivePriceForTick(
        int24 tick,
        uint256 assetPrice,
        uint256 longTradingExpo,
        HugeUint.Uint512 memory accumulator
    ) external pure returns (uint128 price_) {
        return Utils._getEffectivePriceForTick(tick, assetPrice, longTradingExpo, accumulator);
    }

    /// @inheritdoc IUsdnProtocolFallback
    function previewDeposit(uint256 amount, uint128 price, uint128 timestamp)
        external
        view
        returns (uint256 usdnSharesExpected_, uint256 sdexToBurn_)
    {
        Storage storage s = Utils._getMainStorage();

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
        Storage storage s = Utils._getMainStorage();

        uint256 available = Vault.vaultAssetAvailableWithFunding(price, timestamp);
        assetExpected_ = Utils._calcAmountToWithdraw(usdnShares, available, s._usdn.totalShares(), s._vaultFeeBps);
    }

    /// @inheritdoc IUsdnProtocolFallback
    function burnSdex() external whenNotPaused initializedAndNonReentrant {
        IERC20Metadata sdex = Utils._getMainStorage()._sdex;

        uint256 sdexToBurn = sdex.balanceOf(address(this));
        uint256 rewards = FixedPointMathLib.fullMulDiv(sdexToBurn, 100, Constants.BPS_DIVISOR);
        // the rewards are capped at 10% of the total SDEX, so the subtraction is safe
        unchecked {
            sdexToBurn -= rewards;
        }

        if (rewards > 0) {
            address(sdex).safeTransfer(msg.sender, rewards);
        }
        if (sdexToBurn > 0) {
            address(sdex).safeTransfer(Constants.DEAD_ADDRESS, sdexToBurn);
            emit SdexBurned(sdexToBurn, rewards);
        }
    }

    /// @inheritdoc IUsdnProtocolFallback
    function refundSecurityDeposit(address payable validator) external whenNotPaused initializedAndNonReentrant {
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
        initializedAndNonReentrant
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
        initializedAndNonReentrant
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

    /* -------------------------------------------------------------------------- */
    /*                             Immutables getters                             */
    /* -------------------------------------------------------------------------- */

    /// @inheritdoc IUsdnProtocolFallback
    function getTickSpacing() external view returns (int24 tickSpacing_) {
        return Utils._getMainStorage()._tickSpacing;
    }

    /// @inheritdoc IUsdnProtocolFallback
    function getAsset() external view returns (IERC20Metadata asset_) {
        return Utils._getMainStorage()._asset;
    }

    /// @inheritdoc IUsdnProtocolFallback
    function getSdex() external view returns (IERC20Metadata sdex_) {
        return Utils._getMainStorage()._sdex;
    }

    /// @inheritdoc IUsdnProtocolFallback
    function getPriceFeedDecimals() external view returns (uint8 decimals_) {
        return Utils._getMainStorage()._priceFeedDecimals;
    }

    /// @inheritdoc IUsdnProtocolFallback
    function getAssetDecimals() external view returns (uint8 decimals_) {
        return Utils._getMainStorage()._assetDecimals;
    }

    /// @inheritdoc IUsdnProtocolFallback
    function getUsdn() external view returns (IUsdn usdn_) {
        return Utils._getMainStorage()._usdn;
    }

    /// @inheritdoc IUsdnProtocolFallback
    function getUsdnMinDivisor() external view returns (uint256 minDivisor_) {
        return Utils._getMainStorage()._usdnMinDivisor;
    }

    /* -------------------------------------------------------------------------- */
    /*                             Parameters getters                             */
    /* -------------------------------------------------------------------------- */

    /// @inheritdoc IUsdnProtocolFallback
    function getOracleMiddleware() external view returns (IBaseOracleMiddleware oracleMiddleware_) {
        return Utils._getMainStorage()._oracleMiddleware;
    }

    /// @inheritdoc IUsdnProtocolFallback
    function getLiquidationRewardsManager()
        external
        view
        returns (IBaseLiquidationRewardsManager liquidationRewardsManager_)
    {
        return Utils._getMainStorage()._liquidationRewardsManager;
    }

    /// @inheritdoc IUsdnProtocolFallback
    function getRebalancer() external view returns (IBaseRebalancer rebalancer_) {
        return Utils._getMainStorage()._rebalancer;
    }

    /// @inheritdoc IUsdnProtocolFallback
    function getMinLeverage() external view returns (uint256 minLeverage_) {
        return Utils._getMainStorage()._minLeverage;
    }

    /// @inheritdoc IUsdnProtocolFallback
    function getMaxLeverage() external view returns (uint256 maxLeverage_) {
        return Utils._getMainStorage()._maxLeverage;
    }

    /// @inheritdoc IUsdnProtocolFallback
    function getLowLatencyValidatorDeadline() external view returns (uint128 deadline_) {
        return Utils._getMainStorage()._lowLatencyValidatorDeadline;
    }

    /// @inheritdoc IUsdnProtocolFallback
    function getOnChainValidatorDeadline() external view returns (uint128 deadline_) {
        return Utils._getMainStorage()._onChainValidatorDeadline;
    }

    /// @inheritdoc IUsdnProtocolFallback
    function getLiquidationPenalty() external view returns (uint24 liquidationPenalty_) {
        return Utils._getMainStorage()._liquidationPenalty;
    }

    /// @inheritdoc IUsdnProtocolFallback
    function getSafetyMarginBps() external view returns (uint256 safetyMarginBps_) {
        return Utils._getMainStorage()._safetyMarginBps;
    }

    /// @inheritdoc IUsdnProtocolFallback
    function getLiquidationIteration() external view returns (uint16 iterations_) {
        return Utils._getMainStorage()._liquidationIteration;
    }

    /// @inheritdoc IUsdnProtocolFallback
    function getEMAPeriod() external view returns (uint128 period_) {
        return Utils._getMainStorage()._EMAPeriod;
    }

    /// @inheritdoc IUsdnProtocolFallback
    function getFundingSF() external view returns (uint256 scalingFactor_) {
        return Utils._getMainStorage()._fundingSF;
    }

    /// @inheritdoc IUsdnProtocolFallback
    function getProtocolFeeBps() external view returns (uint16 feeBps_) {
        return Utils._getMainStorage()._protocolFeeBps;
    }

    /// @inheritdoc IUsdnProtocolFallback
    function getPositionFeeBps() external view returns (uint16 feeBps_) {
        return Utils._getMainStorage()._positionFeeBps;
    }

    /// @inheritdoc IUsdnProtocolFallback
    function getVaultFeeBps() external view returns (uint16 feeBps_) {
        return Utils._getMainStorage()._vaultFeeBps;
    }

    /// @inheritdoc IUsdnProtocolFallback
    function getRebalancerBonusBps() external view returns (uint16 bonusBps_) {
        return Utils._getMainStorage()._rebalancerBonusBps;
    }

    /// @inheritdoc IUsdnProtocolFallback
    function getSdexBurnOnDepositRatio() external view returns (uint32 ratio_) {
        return Utils._getMainStorage()._sdexBurnOnDepositRatio;
    }

    /// @inheritdoc IUsdnProtocolFallback
    function getSecurityDepositValue() external view returns (uint64 securityDeposit_) {
        return Utils._getMainStorage()._securityDepositValue;
    }

    /// @inheritdoc IUsdnProtocolFallback
    function getFeeThreshold() external view returns (uint256 threshold_) {
        return Utils._getMainStorage()._feeThreshold;
    }

    /// @inheritdoc IUsdnProtocolFallback
    function getFeeCollector() external view returns (address feeCollector_) {
        return Utils._getMainStorage()._feeCollector;
    }

    /// @inheritdoc IUsdnProtocolFallback
    function getMiddlewareValidationDelay() external view returns (uint256 delay_) {
        return Utils._getMainStorage()._oracleMiddleware.getValidationDelay();
    }

    /// @inheritdoc IUsdnProtocolFallback
    function getTargetUsdnPrice() external view returns (uint128 price_) {
        return Utils._getMainStorage()._targetUsdnPrice;
    }

    /// @inheritdoc IUsdnProtocolFallback
    function getUsdnRebaseThreshold() external view returns (uint128 threshold_) {
        return Utils._getMainStorage()._usdnRebaseThreshold;
    }

    /// @inheritdoc IUsdnProtocolFallback
    function getMinLongPosition() external view returns (uint256 minLongPosition_) {
        return Utils._getMainStorage()._minLongPosition;
    }

    /* -------------------------------------------------------------------------- */
    /*                                State getters                               */
    /* -------------------------------------------------------------------------- */

    /// @inheritdoc IUsdnProtocolFallback
    function getLastFundingPerDay() external view returns (int256 lastFunding_) {
        return Utils._getMainStorage()._lastFundingPerDay;
    }

    /// @inheritdoc IUsdnProtocolFallback
    function getLastPrice() external view returns (uint128 lastPrice_) {
        return Utils._getMainStorage()._lastPrice;
    }

    /// @inheritdoc IUsdnProtocolFallback
    function getLastUpdateTimestamp() external view returns (uint128 lastTimestamp_) {
        return Utils._getMainStorage()._lastUpdateTimestamp;
    }

    /// @inheritdoc IUsdnProtocolFallback
    function getPendingProtocolFee() external view returns (uint256 protocolFees_) {
        return Utils._getMainStorage()._pendingProtocolFee;
    }

    /// @inheritdoc IUsdnProtocolFallback
    function getBalanceVault() external view returns (uint256 balanceVault_) {
        return Utils._getMainStorage()._balanceVault;
    }

    /// @inheritdoc IUsdnProtocolFallback
    function getPendingBalanceVault() external view returns (int256 pendingBalanceVault_) {
        return Utils._getMainStorage()._pendingBalanceVault;
    }

    /// @inheritdoc IUsdnProtocolFallback
    function getEMA() external view returns (int256 ema_) {
        return Utils._getMainStorage()._EMA;
    }

    /// @inheritdoc IUsdnProtocolFallback
    function getBalanceLong() external view returns (uint256 balanceLong_) {
        return Utils._getMainStorage()._balanceLong;
    }

    /// @inheritdoc IUsdnProtocolFallback
    function getTotalExpo() external view returns (uint256 totalExpo_) {
        return Utils._getMainStorage()._totalExpo;
    }

    /// @inheritdoc IUsdnProtocolFallback
    function getLiqMultiplierAccumulator() external view returns (HugeUint.Uint512 memory accumulator_) {
        return Utils._getMainStorage()._liqMultiplierAccumulator;
    }

    /// @inheritdoc IUsdnProtocolFallback
    function getTickVersion(int24 tick) external view returns (uint256 tickVersion_) {
        return Utils._getMainStorage()._tickVersion[tick];
    }

    /// @inheritdoc IUsdnProtocolFallback
    function getTickData(int24 tick) external view returns (TickData memory tickData_) {
        Storage storage s = Utils._getMainStorage();

        bytes32 cachedTickHash = Utils._tickHash(tick, s._tickVersion[tick]);
        return Utils._getMainStorage()._tickData[cachedTickHash];
    }

    /// @inheritdoc IUsdnProtocolFallback
    function getCurrentLongPosition(int24 tick, uint256 index) external view returns (Position memory position_) {
        Storage storage s = Utils._getMainStorage();

        uint256 version = s._tickVersion[tick];
        bytes32 cachedTickHash = Utils._tickHash(tick, version);
        return Utils._getMainStorage()._longPositions[cachedTickHash][index];
    }

    /// @inheritdoc IUsdnProtocolFallback
    function getHighestPopulatedTick() external view returns (int24 tick_) {
        Storage storage s = Utils._getMainStorage();

        return Long._findHighestPopulatedTick(s._highestPopulatedTick);
    }

    /// @inheritdoc IUsdnProtocolFallback
    function getTotalLongPositions() external view returns (uint256 totalLongPositions_) {
        return Utils._getMainStorage()._totalLongPositions;
    }

    /// @inheritdoc IUsdnProtocolFallback
    function getDepositExpoImbalanceLimitBps() external view returns (int256 depositExpoImbalanceLimitBps_) {
        return Utils._getMainStorage()._depositExpoImbalanceLimitBps;
    }

    /// @inheritdoc IUsdnProtocolFallback
    function getWithdrawalExpoImbalanceLimitBps() external view returns (int256 withdrawalExpoImbalanceLimitBps_) {
        return Utils._getMainStorage()._withdrawalExpoImbalanceLimitBps;
    }

    /// @inheritdoc IUsdnProtocolFallback
    function getOpenExpoImbalanceLimitBps() external view returns (int256 openExpoImbalanceLimitBps_) {
        return Utils._getMainStorage()._openExpoImbalanceLimitBps;
    }

    /// @inheritdoc IUsdnProtocolFallback
    function getCloseExpoImbalanceLimitBps() external view returns (int256 closeExpoImbalanceLimitBps_) {
        return Utils._getMainStorage()._closeExpoImbalanceLimitBps;
    }

    /// @inheritdoc IUsdnProtocolFallback
    function getRebalancerCloseExpoImbalanceLimitBps()
        external
        view
        returns (int256 rebalancerCloseExpoImbalanceLimitBps_)
    {
        return Utils._getMainStorage()._rebalancerCloseExpoImbalanceLimitBps;
    }

    /// @inheritdoc IUsdnProtocolFallback
    function getLongImbalanceTargetBps() external view returns (int256 longImbalanceTargetBps_) {
        return Utils._getMainStorage()._longImbalanceTargetBps;
    }

    /// @inheritdoc IUsdnProtocolFallback
    function getFallbackAddress() external view returns (address fallback_) {
        return Utils._getMainStorage()._protocolFallbackAddr;
    }

    /// @inheritdoc IUsdnProtocolFallback
    function isPaused() external view returns (bool isPaused_) {
        return paused();
    }

    /// @inheritdoc IUsdnProtocolFallback
    function getNonce(address user) external view returns (uint256 nonce_) {
        return Utils._getMainStorage()._nonce[user];
    }

    /* -------------------------------------------------------------------------- */
    /*                              SET_EXTERNAL_ROLE                             */
    /* -------------------------------------------------------------------------- */

    /// @inheritdoc IUsdnProtocolFallback
    function setOracleMiddleware(IBaseOracleMiddleware newOracleMiddleware)
        external
        onlyRole(Constants.SET_EXTERNAL_ROLE)
    {
        Setters.setOracleMiddleware(newOracleMiddleware);
    }

    /// @inheritdoc IUsdnProtocolFallback
    function setLiquidationRewardsManager(IBaseLiquidationRewardsManager newLiquidationRewardsManager)
        external
        onlyRole(Constants.SET_EXTERNAL_ROLE)
    {
        Setters.setLiquidationRewardsManager(newLiquidationRewardsManager);
    }

    /// @inheritdoc IUsdnProtocolFallback
    function setRebalancer(IBaseRebalancer newRebalancer) external onlyRole(Constants.SET_EXTERNAL_ROLE) {
        Setters.setRebalancer(newRebalancer);
    }

    /// @inheritdoc IUsdnProtocolFallback
    function setFeeCollector(address newFeeCollector) external onlyRole(Constants.SET_EXTERNAL_ROLE) {
        Setters.setFeeCollector(newFeeCollector);
    }

    /* -------------------------------------------------------------------------- */
    /*                           CRITICAL_FUNCTIONS_ROLE                          */
    /* -------------------------------------------------------------------------- */

    /// @inheritdoc IUsdnProtocolFallback
    function setValidatorDeadlines(uint128 newLowLatencyValidatorDeadline, uint128 newOnChainValidatorDeadline)
        external
        onlyRole(Constants.CRITICAL_FUNCTIONS_ROLE)
    {
        Setters.setValidatorDeadlines(newLowLatencyValidatorDeadline, newOnChainValidatorDeadline);
    }

    /* -------------------------------------------------------------------------- */
    /*                          SET_PROTOCOL_PARAMS_ROLE                          */
    /* -------------------------------------------------------------------------- */

    /// @inheritdoc IUsdnProtocolFallback
    function setMinLeverage(uint256 newMinLeverage) external onlyRole(Constants.SET_PROTOCOL_PARAMS_ROLE) {
        Setters.setMinLeverage(newMinLeverage);
    }

    /// @inheritdoc IUsdnProtocolFallback
    function setMaxLeverage(uint256 newMaxLeverage) external onlyRole(Constants.SET_PROTOCOL_PARAMS_ROLE) {
        Setters.setMaxLeverage(newMaxLeverage);
    }

    /// @inheritdoc IUsdnProtocolFallback
    function setLiquidationPenalty(uint24 newLiquidationPenalty)
        external
        onlyRole(Constants.SET_PROTOCOL_PARAMS_ROLE)
    {
        Setters.setLiquidationPenalty(newLiquidationPenalty);
    }

    /// @inheritdoc IUsdnProtocolFallback
    function setEMAPeriod(uint128 newEMAPeriod) external onlyRole(Constants.SET_PROTOCOL_PARAMS_ROLE) {
        Setters.setEMAPeriod(newEMAPeriod);
    }

    /// @inheritdoc IUsdnProtocolFallback
    function setFundingSF(uint256 newFundingSF) external onlyRole(Constants.SET_PROTOCOL_PARAMS_ROLE) {
        Setters.setFundingSF(newFundingSF);
    }

    /// @inheritdoc IUsdnProtocolFallback
    function setProtocolFeeBps(uint16 newProtocolFeeBps) external onlyRole(Constants.SET_PROTOCOL_PARAMS_ROLE) {
        Setters.setProtocolFeeBps(newProtocolFeeBps);
    }

    /// @inheritdoc IUsdnProtocolFallback
    function setPositionFeeBps(uint16 newPositionFee) external onlyRole(Constants.SET_PROTOCOL_PARAMS_ROLE) {
        Setters.setPositionFeeBps(newPositionFee);
    }

    /// @inheritdoc IUsdnProtocolFallback
    function setVaultFeeBps(uint16 newVaultFee) external onlyRole(Constants.SET_PROTOCOL_PARAMS_ROLE) {
        Setters.setVaultFeeBps(newVaultFee);
    }

    /// @inheritdoc IUsdnProtocolFallback
    function setRebalancerBonusBps(uint16 newBonus) external onlyRole(Constants.SET_PROTOCOL_PARAMS_ROLE) {
        Setters.setRebalancerBonusBps(newBonus);
    }

    /// @inheritdoc IUsdnProtocolFallback
    function setSdexBurnOnDepositRatio(uint32 newRatio) external onlyRole(Constants.SET_PROTOCOL_PARAMS_ROLE) {
        Setters.setSdexBurnOnDepositRatio(newRatio);
    }

    /// @inheritdoc IUsdnProtocolFallback
    function setSecurityDepositValue(uint64 securityDepositValue)
        external
        onlyRole(Constants.SET_PROTOCOL_PARAMS_ROLE)
    {
        Setters.setSecurityDepositValue(securityDepositValue);
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
        Setters.setExpoImbalanceLimits(
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
        Setters.setMinLongPosition(newMinLongPosition);
    }

    /* -------------------------------------------------------------------------- */
    /*                              SET_OPTIONS_ROLE                              */
    /* -------------------------------------------------------------------------- */

    /// @inheritdoc IUsdnProtocolFallback
    function setSafetyMarginBps(uint256 newSafetyMarginBps) external onlyRole(Constants.SET_OPTIONS_ROLE) {
        Setters.setSafetyMarginBps(newSafetyMarginBps);
    }

    /// @inheritdoc IUsdnProtocolFallback
    function setLiquidationIteration(uint16 newLiquidationIteration) external onlyRole(Constants.SET_OPTIONS_ROLE) {
        Setters.setLiquidationIteration(newLiquidationIteration);
    }

    /// @inheritdoc IUsdnProtocolFallback
    function setFeeThreshold(uint256 newFeeThreshold) external onlyRole(Constants.SET_OPTIONS_ROLE) {
        Setters.setFeeThreshold(newFeeThreshold);
    }

    /* -------------------------------------------------------------------------- */
    /*                            SET_USDN_PARAMS_ROLE                            */
    /* -------------------------------------------------------------------------- */

    /// @inheritdoc IUsdnProtocolFallback
    function setTargetUsdnPrice(uint128 newPrice) external onlyRole(Constants.SET_USDN_PARAMS_ROLE) {
        Setters.setTargetUsdnPrice(newPrice);
    }

    /// @inheritdoc IUsdnProtocolFallback
    function setUsdnRebaseThreshold(uint128 newThreshold) external onlyRole(Constants.SET_USDN_PARAMS_ROLE) {
        Setters.setUsdnRebaseThreshold(newThreshold);
    }

    /* -------------------------------------------------------------------------- */
    /*                                 PAUSER_ROLE                                */
    /* -------------------------------------------------------------------------- */

    /// @inheritdoc IUsdnProtocolFallback
    function pause() external onlyRole(Constants.PAUSER_ROLE) {
        Core._applyPnlAndFunding(Utils._getMainStorage()._lastPrice, uint128(block.timestamp));
        _pause();
    }

    /// @inheritdoc IUsdnProtocolFallback
    function pauseSafe() external onlyRole(Constants.PAUSER_ROLE) {
        _pause();
    }

    /* -------------------------------------------------------------------------- */
    /*                                UNPAUSER_ROLE                               */
    /* -------------------------------------------------------------------------- */

    /// @inheritdoc IUsdnProtocolFallback
    function unpause() external onlyRole(Constants.UNPAUSER_ROLE) {
        Utils._getMainStorage()._lastUpdateTimestamp = uint128(block.timestamp);
        _unpause();
    }

    /// @inheritdoc IUsdnProtocolFallback
    function unpauseSafe() external onlyRole(Constants.UNPAUSER_ROLE) {
        _unpause();
    }
}

// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.25;

import { AccessControlDefaultAdminRules } from
    "@openzeppelin/contracts/access/extensions/AccessControlDefaultAdminRules.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { IBaseLiquidationRewardsManager } from "../interfaces/OracleMiddleware/IBaseLiquidationRewardsManager.sol";
import { IBaseOracleMiddleware } from "../interfaces/OracleMiddleware/IBaseOracleMiddleware.sol";
import { IBaseRebalancer } from "../interfaces/Rebalancer/IBaseRebalancer.sol";
import { IUsdn } from "../interfaces/Usdn/IUsdn.sol";
import { IUsdnProtocolErrors } from "../interfaces/UsdnProtocol/IUsdnProtocolErrors.sol";
import { IUsdnProtocolStorage } from "../interfaces/UsdnProtocol/IUsdnProtocolStorage.sol";
import { DoubleEndedQueue } from "../libraries/DoubleEndedQueue.sol";
import { HugeUint } from "../libraries/HugeUint.sol";
import { InitializableReentrancyGuard } from "../utils/InitializableReentrancyGuard.sol";
import { UsdnProtocolConstantsLibrary as Constants } from "./libraries/UsdnProtocolConstantsLibrary.sol";
import { UsdnProtocolCoreLibrary as Core } from "./libraries/UsdnProtocolCoreLibrary.sol";

abstract contract UsdnProtocolStorage is
    IUsdnProtocolErrors,
    IUsdnProtocolStorage,
    InitializableReentrancyGuard,
    AccessControlDefaultAdminRules
{
    using DoubleEndedQueue for DoubleEndedQueue.Deque;

    /// @notice The storage structure of the Usdn protocol
    Storage internal s;

    /// @inheritdoc IUsdnProtocolStorage
    bytes32 public constant SET_EXTERNAL_ROLE = keccak256("SET_EXTERNAL_ROLE");

    /// @inheritdoc IUsdnProtocolStorage
    bytes32 public constant CRITICAL_FUNCTIONS_ROLE = keccak256("CRITICAL_FUNCTIONS_ROLE");

    /// @inheritdoc IUsdnProtocolStorage
    bytes32 public constant SET_PROTOCOL_PARAMS_ROLE = keccak256("SET_PROTOCOL_PARAMS_ROLE");

    /// @inheritdoc IUsdnProtocolStorage
    bytes32 public constant SET_USDN_PARAMS_ROLE = keccak256("SET_USDN_PARAMS_ROLE");

    /// @inheritdoc IUsdnProtocolStorage
    bytes32 public constant SET_OPTIONS_ROLE = keccak256("SET_OPTIONS_ROLE");

    /// @inheritdoc IUsdnProtocolStorage
    bytes32 public constant ADMIN_SET_EXTERNAL_ROLE = keccak256("ADMIN_SET_EXTERNAL_ROLE");

    /// @inheritdoc IUsdnProtocolStorage
    bytes32 public constant ADMIN_CRITICAL_FUNCTIONS_ROLE = keccak256("ADMIN_CRITICAL_FUNCTIONS_ROLE");

    /// @inheritdoc IUsdnProtocolStorage
    bytes32 public constant ADMIN_SET_PROTOCOL_PARAMS_ROLE = keccak256("ADMIN_SET_PROTOCOL_PARAMS_ROLE");

    /// @inheritdoc IUsdnProtocolStorage
    bytes32 public constant ADMIN_SET_USDN_PARAMS_ROLE = keccak256("ADMIN_SET_USDN_PARAMS_ROLE");

    /// @inheritdoc IUsdnProtocolStorage
    bytes32 public constant ADMIN_SET_OPTIONS_ROLE = keccak256("ADMIN_SET_OPTIONS_ROLE");

    /// @inheritdoc IUsdnProtocolStorage
    function LEVERAGE_DECIMALS() external pure returns (uint8) {
        return Constants.LEVERAGE_DECIMALS;
    }

    /// @inheritdoc IUsdnProtocolStorage
    function FUNDING_RATE_DECIMALS() external pure returns (uint8) {
        return Constants.FUNDING_RATE_DECIMALS;
    }

    /// @inheritdoc IUsdnProtocolStorage
    function TOKENS_DECIMALS() external pure returns (uint8) {
        return Constants.TOKENS_DECIMALS;
    }

    /// @inheritdoc IUsdnProtocolStorage
    function LIQUIDATION_MULTIPLIER_DECIMALS() external pure returns (uint8) {
        return Constants.LIQUIDATION_MULTIPLIER_DECIMALS;
    }

    /// @inheritdoc IUsdnProtocolStorage
    function FUNDING_SF_DECIMALS() external pure returns (uint8) {
        return Constants.FUNDING_SF_DECIMALS;
    }

    /// @inheritdoc IUsdnProtocolStorage
    function SDEX_BURN_ON_DEPOSIT_DIVISOR() external pure returns (uint256) {
        return Constants.SDEX_BURN_ON_DEPOSIT_DIVISOR;
    }

    /// @inheritdoc IUsdnProtocolStorage
    function BPS_DIVISOR() external pure returns (uint256) {
        return Constants.BPS_DIVISOR;
    }

    /// @inheritdoc IUsdnProtocolStorage
    function MAX_LIQUIDATION_ITERATION() external pure returns (uint16) {
        return Constants.MAX_LIQUIDATION_ITERATION;
    }

    /// @inheritdoc IUsdnProtocolStorage
    function NO_POSITION_TICK() external pure returns (int24) {
        return Constants.NO_POSITION_TICK;
    }

    /// @inheritdoc IUsdnProtocolStorage
    function DEAD_ADDRESS() external pure returns (address) {
        return Constants.DEAD_ADDRESS;
    }

    /// @inheritdoc IUsdnProtocolStorage
    function MIN_USDN_SUPPLY() external pure returns (uint256) {
        return Constants.MIN_USDN_SUPPLY;
    }

    /// @inheritdoc IUsdnProtocolStorage
    function MIN_INIT_DEPOSIT() external pure returns (uint256) {
        return Constants.MIN_INIT_DEPOSIT;
    }

    /// @inheritdoc IUsdnProtocolStorage
    function MAX_ACTIONABLE_PENDING_ACTIONS() external pure returns (uint256) {
        return Constants.MAX_ACTIONABLE_PENDING_ACTIONS;
    }

    /* -------------------------------------------------------------------------- */
    /*                                 Immutables getters                         */
    /* -------------------------------------------------------------------------- */

    /// @inheritdoc IUsdnProtocolStorage
    function getTickSpacing() external view returns (int24) {
        return s._tickSpacing;
    }

    /// @inheritdoc IUsdnProtocolStorage
    function getAsset() external view returns (IERC20Metadata) {
        return s._asset;
    }

    /// @inheritdoc IUsdnProtocolStorage
    function getSdex() external view returns (IERC20Metadata) {
        return s._sdex;
    }

    /// @inheritdoc IUsdnProtocolStorage
    function getPriceFeedDecimals() external view returns (uint8) {
        return s._priceFeedDecimals;
    }

    /// @inheritdoc IUsdnProtocolStorage
    function getAssetDecimals() external view returns (uint8) {
        return s._assetDecimals;
    }

    /// @inheritdoc IUsdnProtocolStorage
    function getUsdn() external view returns (IUsdn) {
        return s._usdn;
    }

    /// @inheritdoc IUsdnProtocolStorage
    function getUsdnMinDivisor() external view returns (uint256) {
        return s._usdnMinDivisor;
    }

    /* -------------------------------------------------------------------------- */
    /*                                 Parameters getters                         */
    /* -------------------------------------------------------------------------- */

    /// @inheritdoc IUsdnProtocolStorage
    function getOracleMiddleware() external view returns (IBaseOracleMiddleware) {
        return s._oracleMiddleware;
    }

    /// @inheritdoc IUsdnProtocolStorage
    function getLiquidationRewardsManager() external view returns (IBaseLiquidationRewardsManager) {
        return s._liquidationRewardsManager;
    }

    /// @inheritdoc IUsdnProtocolStorage
    function getRebalancer() external view returns (IBaseRebalancer) {
        return s._rebalancer;
    }

    /// @inheritdoc IUsdnProtocolStorage
    function getMinLeverage() external view returns (uint256) {
        return s._minLeverage;
    }

    /// @inheritdoc IUsdnProtocolStorage
    function getMaxLeverage() external view returns (uint256) {
        return s._maxLeverage;
    }

    /// @inheritdoc IUsdnProtocolStorage
    function getValidationDeadline() external view returns (uint256) {
        return s._validationDeadline;
    }

    /// @inheritdoc IUsdnProtocolStorage
    function getLiquidationPenalty() external view returns (uint8) {
        return s._liquidationPenalty;
    }

    /// @inheritdoc IUsdnProtocolStorage
    function getSafetyMarginBps() external view returns (uint256) {
        return s._safetyMarginBps;
    }

    /// @inheritdoc IUsdnProtocolStorage
    function getLiquidationIteration() external view returns (uint16) {
        return s._liquidationIteration;
    }

    /// @inheritdoc IUsdnProtocolStorage
    function getEMAPeriod() external view returns (uint128) {
        return s._EMAPeriod;
    }

    /// @inheritdoc IUsdnProtocolStorage
    function getFundingSF() external view returns (uint256) {
        return s._fundingSF;
    }

    /// @inheritdoc IUsdnProtocolStorage
    function getProtocolFeeBps() external view returns (uint16) {
        return s._protocolFeeBps;
    }

    /// @inheritdoc IUsdnProtocolStorage
    function getPositionFeeBps() external view returns (uint16) {
        return s._positionFeeBps;
    }

    /// @inheritdoc IUsdnProtocolStorage
    function getVaultFeeBps() external view returns (uint16) {
        return s._vaultFeeBps;
    }

    /// @inheritdoc IUsdnProtocolStorage
    function getRebalancerBonusBps() external view returns (uint16) {
        return s._rebalancerBonusBps;
    }

    /// @inheritdoc IUsdnProtocolStorage
    function getSdexBurnOnDepositRatio() external view returns (uint32) {
        return s._sdexBurnOnDepositRatio;
    }

    /// @inheritdoc IUsdnProtocolStorage
    function getSecurityDepositValue() external view returns (uint64) {
        return s._securityDepositValue;
    }

    /// @inheritdoc IUsdnProtocolStorage
    function getFeeThreshold() external view returns (uint256) {
        return s._feeThreshold;
    }

    /// @inheritdoc IUsdnProtocolStorage
    function getFeeCollector() external view returns (address) {
        return s._feeCollector;
    }

    /// @inheritdoc IUsdnProtocolStorage
    function getMiddlewareValidationDelay() external view returns (uint256) {
        return s._oracleMiddleware.getValidationDelay();
    }

    /// @inheritdoc IUsdnProtocolStorage
    function getTargetUsdnPrice() external view returns (uint128) {
        return s._targetUsdnPrice;
    }

    /// @inheritdoc IUsdnProtocolStorage
    function getUsdnRebaseThreshold() external view returns (uint128) {
        return s._usdnRebaseThreshold;
    }

    /// @inheritdoc IUsdnProtocolStorage
    function getUsdnRebaseInterval() external view returns (uint256) {
        return s._usdnRebaseInterval;
    }

    /// @inheritdoc IUsdnProtocolStorage
    function getMinLongPosition() external view returns (uint256) {
        return s._minLongPosition;
    }

    /* -------------------------------------------------------------------------- */
    /*                                    State getters                           */
    /* -------------------------------------------------------------------------- */

    /// @inheritdoc IUsdnProtocolStorage
    function getLastFundingPerDay() external view returns (int256) {
        return s._lastFundingPerDay;
    }

    /// @inheritdoc IUsdnProtocolStorage
    function getLastPrice() external view returns (uint128) {
        return s._lastPrice;
    }

    /// @inheritdoc IUsdnProtocolStorage
    function getLastUpdateTimestamp() external view returns (uint128) {
        return s._lastUpdateTimestamp;
    }

    /// @inheritdoc IUsdnProtocolStorage
    function getPendingProtocolFee() external view returns (uint256) {
        return s._pendingProtocolFee;
    }

    /// @inheritdoc IUsdnProtocolStorage
    function getBalanceVault() external view returns (uint256) {
        return s._balanceVault;
    }

    /// @inheritdoc IUsdnProtocolStorage
    function getPendingBalanceVault() external view returns (int256) {
        return s._pendingBalanceVault;
    }

    /// @inheritdoc IUsdnProtocolStorage
    function getLastRebaseCheck() external view returns (uint256) {
        return s._lastRebaseCheck;
    }

    /// @inheritdoc IUsdnProtocolStorage
    function getEMA() external view returns (int256) {
        return s._EMA;
    }

    /// @inheritdoc IUsdnProtocolStorage
    function getBalanceLong() external view returns (uint256) {
        return s._balanceLong;
    }

    /// @inheritdoc IUsdnProtocolStorage
    function getTotalExpo() external view returns (uint256) {
        return s._totalExpo;
    }

    /// @inheritdoc IUsdnProtocolStorage
    function getLiqMultiplierAccumulator() external view returns (HugeUint.Uint512 memory) {
        return s._liqMultiplierAccumulator;
    }

    /// @inheritdoc IUsdnProtocolStorage
    function getTickVersion(int24 tick) external view returns (uint256) {
        return s._tickVersion[tick];
    }

    /// @inheritdoc IUsdnProtocolStorage
    function getTickData(int24 tick) external view returns (TickData memory) {
        bytes32 cachedTickHash = Core.tickHash(tick, s._tickVersion[tick]);
        return s._tickData[cachedTickHash];
    }

    /// @inheritdoc IUsdnProtocolStorage
    function getCurrentLongPosition(int24 tick, uint256 index) external view returns (Position memory) {
        uint256 version = s._tickVersion[tick];
        bytes32 cachedTickHash = Core.tickHash(tick, version);
        return s._longPositions[cachedTickHash][index];
    }

    /// @inheritdoc IUsdnProtocolStorage
    function getHighestPopulatedTick() external view returns (int24) {
        return s._highestPopulatedTick;
    }

    /// @inheritdoc IUsdnProtocolStorage
    function getTotalLongPositions() external view returns (uint256) {
        return s._totalLongPositions;
    }

    /// @inheritdoc IUsdnProtocolStorage
    function getDepositExpoImbalanceLimitBps() external view returns (int256 depositExpoImbalanceLimitBps_) {
        depositExpoImbalanceLimitBps_ = s._depositExpoImbalanceLimitBps;
    }

    /// @inheritdoc IUsdnProtocolStorage
    function getWithdrawalExpoImbalanceLimitBps() external view returns (int256 withdrawalExpoImbalanceLimitBps_) {
        withdrawalExpoImbalanceLimitBps_ = s._withdrawalExpoImbalanceLimitBps;
    }

    /// @inheritdoc IUsdnProtocolStorage
    function getOpenExpoImbalanceLimitBps() external view returns (int256 openExpoImbalanceLimitBps_) {
        openExpoImbalanceLimitBps_ = s._openExpoImbalanceLimitBps;
    }

    /// @inheritdoc IUsdnProtocolStorage
    function getCloseExpoImbalanceLimitBps() external view returns (int256 closeExpoImbalanceLimitBps_) {
        closeExpoImbalanceLimitBps_ = s._closeExpoImbalanceLimitBps;
    }

    /// @inheritdoc IUsdnProtocolStorage
    function getLongImbalanceTargetBps() external view returns (int256 longImbalanceTargetBps_) {
        longImbalanceTargetBps_ = s._longImbalanceTargetBps;
    }
}

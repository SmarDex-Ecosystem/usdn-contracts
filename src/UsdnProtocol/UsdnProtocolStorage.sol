// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.25;

import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { LibBitmap } from "solady/src/utils/LibBitmap.sol";
import { Ownable2Step } from "@openzeppelin/contracts/access/Ownable2Step.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

import { IUsdnProtocolStorage } from "../interfaces/UsdnProtocol/IUsdnProtocolStorage.sol";
import { InitializableReentrancyGuard } from "../utils/InitializableReentrancyGuard.sol";
import { IUsdn } from "../interfaces/Usdn/IUsdn.sol";
import { IBaseLiquidationRewardsManager } from "../interfaces/OracleMiddleware/IBaseLiquidationRewardsManager.sol";
import { IBaseOracleMiddleware } from "../interfaces/OracleMiddleware/IBaseOracleMiddleware.sol";
import { IBaseRebalancer } from "../interfaces/Rebalancer/IBaseRebalancer.sol";
import { PendingAction, TickData } from "../interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import { DoubleEndedQueue } from "../libraries/DoubleEndedQueue.sol";
import { HugeUint } from "../libraries/HugeUint.sol";
import { IUsdnProtocolErrors } from "./../interfaces/UsdnProtocol/IUsdnProtocolErrors.sol";
import { UsdnProtocolActionsLongLibrary as actionsLongLib } from "./libraries/UsdnProtocolActionsLongLibrary.sol";
import { UsdnProtocolConstantsLibrary as constantsLib } from "./libraries/UsdnProtocolConstantsLibrary.sol";
import { Position } from "../interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";

contract UsdnProtocolStorage is
    IUsdnProtocolErrors,
    IUsdnProtocolStorage,
    InitializableReentrancyGuard,
    Ownable2Step
{
    using DoubleEndedQueue for DoubleEndedQueue.Deque;

    /// @notice The storage structure of the Usdn protocol
    Storage internal s;

    /**
     * @notice Constructor
     * @param usdn The USDN ERC20 contract
     * @param sdex The SDEX ERC20 contract
     * @param asset The asset ERC20 contract (wstETH)
     * @param oracleMiddleware The oracle middleware contract
     * @param liquidationRewardsManager The liquidation rewards manager contract
     * @param tickSpacing The positions tick spacing
     * @param feeCollector The address of the fee collector
     */
    constructor(
        IUsdn usdn,
        IERC20Metadata sdex,
        IERC20Metadata asset,
        IBaseOracleMiddleware oracleMiddleware,
        IBaseLiquidationRewardsManager liquidationRewardsManager,
        int24 tickSpacing,
        address feeCollector
    ) Ownable(msg.sender) {
        // // constants
        // constantsLib.LEVERAGE_DECIMALS = 21;
        // constantsLib.FUNDING_RATE_DECIMALS = 18;
        // constantsLib.TOKENS_DECIMALS = 18;
        // constantsLib.LIQUIDATION_MULTIPLIER_DECIMALS = 38;
        // constantsLib.FUNDING_SF_DECIMALS = 3;
        // constantsLib.SDEX_BURN_ON_DEPOSIT_DIVISOR = 1e8;
        // constantsLib.BPS_DIVISOR = 10_000;
        // constantsLib.MAX_LIQUIDATION_ITERATION = 10;
        // constantsLib.NO_POSITION_TICK = type(int24).min;
        // constantsLib.DEAD_ADDRESS = address(0xdead);
        // constantsLib.MIN_USDN_SUPPLY = 1000;
        // constantsLib.MIN_INIT_DEPOSIT = 1 ether;

        // parameters
        s._minLeverage = 10 ** constantsLib.LEVERAGE_DECIMALS + 10 ** 12;
        s._maxLeverage = 10 * 10 ** constantsLib.LEVERAGE_DECIMALS;
        s._validationDeadline = 90 minutes;
        s._safetyMarginBps = 200; // 2%
        s._liquidationIteration = 1;
        s._protocolFeeBps = 800;
        s._rebalancerBonusBps = 8000; // 80%
        s._liquidationPenalty = 2; // 200 ticks -> ~2.02%
        s._EMAPeriod = 5 days;
        s._fundingSF = 12 * 10 ** (constantsLib.FUNDING_SF_DECIMALS - 2);
        s._feeThreshold = 1 ether;
        s._openExpoImbalanceLimitBps = 500;
        s._withdrawalExpoImbalanceLimitBps = 600;
        s._depositExpoImbalanceLimitBps = 500;
        s._closeExpoImbalanceLimitBps = 600;
        s._longImbalanceTargetBps = 550;
        s._positionFeeBps = 4; // 0.04%
        s._vaultFeeBps = 4; // 0.04%
        s._sdexBurnOnDepositRatio = 1e6; // 1%
        s._securityDepositValue = 0.5 ether;

        // Long positions
        s._EMA = int256(3 * 10 ** (constantsLib.FUNDING_RATE_DECIMALS - 4));

        // since all USDN must be minted by the protocol, we check that the total supply is 0
        if (usdn.totalSupply() != 0) {
            revert UsdnProtocolInvalidUsdn(address(usdn));
        }
        if (feeCollector == address(0)) {
            revert UsdnProtocolInvalidFeeCollector();
        }

        s._usdn = usdn;
        s._sdex = sdex;
        // those tokens should have 18 decimals
        if (usdn.decimals() != constantsLib.TOKENS_DECIMALS || sdex.decimals() != constantsLib.TOKENS_DECIMALS) {
            revert UsdnProtocolInvalidTokenDecimals();
        }

        s._usdnMinDivisor = usdn.MIN_DIVISOR();
        s._asset = asset;
        s._assetDecimals = asset.decimals();
        if (s._assetDecimals < constantsLib.FUNDING_SF_DECIMALS) {
            revert UsdnProtocolInvalidAssetDecimals(s._assetDecimals);
        }
        s._oracleMiddleware = oracleMiddleware;
        s._priceFeedDecimals = oracleMiddleware.getDecimals();
        s._liquidationRewardsManager = liquidationRewardsManager;
        s._tickSpacing = tickSpacing;
        s._feeCollector = feeCollector;

        s._targetUsdnPrice = uint128(10_087 * 10 ** (s._priceFeedDecimals - 4)); // $1.0087
        s._usdnRebaseThreshold = uint128(1009 * 10 ** (s._priceFeedDecimals - 3)); // $1.009
        s._minLongPosition = 2 * 10 ** s._assetDecimals;
    }

    /// @inheritdoc IUsdnProtocolStorage
    function LEVERAGE_DECIMALS() external pure returns (uint8) {
        return constantsLib.LEVERAGE_DECIMALS;
    }

    /// @inheritdoc IUsdnProtocolStorage
    function FUNDING_RATE_DECIMALS() external pure returns (uint8) {
        return constantsLib.FUNDING_RATE_DECIMALS;
    }

    /// @inheritdoc IUsdnProtocolStorage
    function TOKENS_DECIMALS() external pure returns (uint8) {
        return constantsLib.TOKENS_DECIMALS;
    }

    /// @inheritdoc IUsdnProtocolStorage
    function LIQUIDATION_MULTIPLIER_DECIMALS() external pure returns (uint8) {
        return constantsLib.LIQUIDATION_MULTIPLIER_DECIMALS;
    }

    /// @inheritdoc IUsdnProtocolStorage
    function FUNDING_SF_DECIMALS() external pure returns (uint8) {
        return constantsLib.FUNDING_SF_DECIMALS;
    }

    /// @inheritdoc IUsdnProtocolStorage
    function SDEX_BURN_ON_DEPOSIT_DIVISOR() external pure returns (uint256) {
        return constantsLib.SDEX_BURN_ON_DEPOSIT_DIVISOR;
    }

    /// @inheritdoc IUsdnProtocolStorage
    function BPS_DIVISOR() external pure returns (uint256) {
        return constantsLib.BPS_DIVISOR;
    }

    /// @inheritdoc IUsdnProtocolStorage
    function MAX_LIQUIDATION_ITERATION() external pure returns (uint16) {
        return constantsLib.MAX_LIQUIDATION_ITERATION;
    }

    /// @inheritdoc IUsdnProtocolStorage
    function NO_POSITION_TICK() external pure returns (int24) {
        return constantsLib.NO_POSITION_TICK;
    }

    /// @inheritdoc IUsdnProtocolStorage
    function DEAD_ADDRESS() external pure returns (address) {
        return constantsLib.DEAD_ADDRESS;
    }

    /// @inheritdoc IUsdnProtocolStorage
    function MIN_USDN_SUPPLY() external pure returns (uint256) {
        return constantsLib.MIN_USDN_SUPPLY;
    }

    /// @inheritdoc IUsdnProtocolStorage
    function MIN_INIT_DEPOSIT() external pure returns (uint256) {
        return constantsLib.MIN_INIT_DEPOSIT;
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
    function getLastFunding() external view returns (int256) {
        return s._lastFunding;
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
    function getPendingAction(address user) external view returns (uint256) {
        return s._pendingActions[user];
    }

    /// @inheritdoc IUsdnProtocolStorage
    function getPendingActionAt(uint256 index) external view returns (PendingAction memory action_) {
        (action_,) = s._pendingActionsQueue.at(index);
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
        bytes32 cachedTickHash = actionsLongLib.tickHash(tick, s._tickVersion[tick]);
        return s._tickData[cachedTickHash];
    }

    /// @inheritdoc IUsdnProtocolStorage
    function getCurrentLongPosition(int24 tick, uint256 index) external view returns (Position memory) {
        uint256 version = s._tickVersion[tick];
        bytes32 cachedTickHash = actionsLongLib.tickHash(tick, version);
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

struct Storage {
    // // constants
    // uint8 LEVERAGE_DECIMALS;
    // uint8 FUNDING_RATE_DECIMALS;
    // uint8 TOKENS_DECIMALS;
    // uint8 LIQUIDATION_MULTIPLIER_DECIMALS;
    // uint8 FUNDING_SF_DECIMALS;
    // uint256 SDEX_BURN_ON_DEPOSIT_DIVISOR;
    // uint256 BPS_DIVISOR;
    // uint16 MAX_LIQUIDATION_ITERATION;
    // int24 NO_POSITION_TICK;
    // address DEAD_ADDRESS;
    // uint256 MIN_USDN_SUPPLY;
    // uint256 MIN_INIT_DEPOSIT;
    // immutable
    int24 _tickSpacing;
    IERC20Metadata _asset;
    uint8 _assetDecimals;
    uint8 _priceFeedDecimals;
    IUsdn _usdn;
    IERC20Metadata _sdex;
    uint256 _usdnMinDivisor;
    // parameters
    IBaseOracleMiddleware _oracleMiddleware;
    IBaseLiquidationRewardsManager _liquidationRewardsManager;
    IBaseRebalancer _rebalancer;
    uint256 _minLeverage;
    uint256 _maxLeverage;
    uint256 _validationDeadline;
    uint256 _safetyMarginBps; // 2%
    uint16 _liquidationIteration;
    uint16 _protocolFeeBps;
    uint16 _rebalancerBonusBps; // 80%
    uint8 _liquidationPenalty; // 200 ticks -> ~2.02%
    uint128 _EMAPeriod;
    uint256 _fundingSF;
    uint256 _feeThreshold;
    int256 _openExpoImbalanceLimitBps;
    int256 _withdrawalExpoImbalanceLimitBps;
    int256 _depositExpoImbalanceLimitBps;
    int256 _closeExpoImbalanceLimitBps;
    int256 _longImbalanceTargetBps;
    uint16 _positionFeeBps; // 0.04%
    uint16 _vaultFeeBps; // 0.04%
    uint32 _sdexBurnOnDepositRatio; // 1%
    address _feeCollector;
    uint64 _securityDepositValue;
    uint128 _targetUsdnPrice;
    uint128 _usdnRebaseThreshold;
    uint256 _usdnRebaseInterval;
    uint256 _minLongPosition;
    // State
    int256 _lastFunding;
    uint128 _lastPrice;
    uint128 _lastUpdateTimestamp;
    uint256 _pendingProtocolFee;
    // Pending actions queue
    mapping(address => uint256) _pendingActions;
    DoubleEndedQueue.Deque _pendingActionsQueue;
    // Vault
    uint256 _balanceVault;
    int256 _pendingBalanceVault;
    uint256 _lastRebaseCheck;
    // Long positions
    int256 _EMA;
    uint256 _balanceLong;
    uint256 _totalExpo;
    HugeUint.Uint512 _liqMultiplierAccumulator;
    mapping(int24 => uint256) _tickVersion;
    mapping(bytes32 => Position[]) _longPositions;
    mapping(bytes32 => TickData) _tickData;
    int24 _highestPopulatedTick;
    uint256 _totalLongPositions;
    LibBitmap.Bitmap _tickBitmap;
}

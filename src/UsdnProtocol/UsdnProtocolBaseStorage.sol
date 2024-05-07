// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { IUsdn } from "src/interfaces/Usdn/IUsdn.sol";
import { IOracleMiddleware } from "src/interfaces/OracleMiddleware/IOracleMiddleware.sol";
import { ILiquidationRewardsManager } from "src/interfaces/OracleMiddleware/ILiquidationRewardsManager.sol";
import { DoubleEndedQueue } from "src/libraries/DoubleEndedQueue.sol";
import { HugeUint } from "src/libraries/HugeUint.sol";
import { Position } from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import { TickData } from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import { LibBitmap } from "solady/src/utils/LibBitmap.sol";

struct Storage {
    // constants
    uint8 LEVERAGE_DECIMALS;
    uint8 FUNDING_RATE_DECIMALS;
    uint8 TOKENS_DECIMALS;
    uint8 LIQUIDATION_MULTIPLIER_DECIMALS;
    uint8 FUNDING_SF_DECIMALS;
    uint256 SDEX_BURN_ON_DEPOSIT_DIVISOR;
    uint256 BPS_DIVISOR;
    uint16 MAX_LIQUIDATION_ITERATION;
    // immutable
    int24 _tickSpacing;
    IERC20Metadata _asset;
    uint8 _assetDecimals;
    uint8 _priceFeedDecimals;
    IUsdn _usdn;
    IERC20Metadata _sdex;
    uint256 _usdnMinDivisor;
    // parameters
    IOracleMiddleware _oracleMiddleware;
    ILiquidationRewardsManager _liquidationRewardsManager;
    uint256 _minLeverage;
    uint256 _maxLeverage;
    uint256 _validationDeadline;
    uint256 _safetyMarginBps;
    uint16 _liquidationIteration;
    uint16 _protocolFeeBps;
    uint8 _liquidationPenalty;
    uint128 _EMAPeriod;
    uint256 _fundingSF;
    uint256 _feeThreshold;
    int256 _openExpoImbalanceLimitBps;
    int256 _withdrawalExpoImbalanceLimitBps;
    int256 _depositExpoImbalanceLimitBps;
    int256 _closeExpoImbalanceLimitBps;
    uint16 _positionFeeBps;
    uint32 _sdexBurnOnDepositRatio;
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

contract BaseStorage {
    Storage internal s;

    constructor() {
        // constants
        s.LEVERAGE_DECIMALS = 21;
        s.FUNDING_RATE_DECIMALS = 18;
        s.TOKENS_DECIMALS = 18;
        s.LIQUIDATION_MULTIPLIER_DECIMALS = 38;
        s.FUNDING_SF_DECIMALS = 3;
        s.SDEX_BURN_ON_DEPOSIT_DIVISOR = 1e8;
        s.BPS_DIVISOR = 10_000;
        s.MAX_LIQUIDATION_ITERATION = 10;
        // Parameters
        s._minLeverage = 10 ** s.LEVERAGE_DECIMALS + 10 ** 12;
        s._maxLeverage = 10 * 10 ** s.LEVERAGE_DECIMALS;
        s._validationDeadline = 20 minutes;
        s._safetyMarginBps = 200; // 2%
        s._liquidationIteration = 1;
        s._protocolFeeBps = 10;
        s._liquidationPenalty = 2; // 200 ticks -> ~2.02%
        s._EMAPeriod = 5 days;
        s._fundingSF = 12 * 10 ** (s.FUNDING_SF_DECIMALS - 2);
        s._feeThreshold = 1 ether;
        s._openExpoImbalanceLimitBps = 200;
        s._withdrawalExpoImbalanceLimitBps = 600;
        s._depositExpoImbalanceLimitBps = 200;
        s._closeExpoImbalanceLimitBps = 600;
        s._positionFeeBps = 4; // 0.04%
        s._sdexBurnOnDepositRatio = 1e6; // 1%
        s._securityDepositValue = 0.5 ether;
        s._usdnRebaseInterval = 0;
        // Long positions
        s._EMA = int256(3 * 10 ** (s.FUNDING_RATE_DECIMALS - 4));
    }
}

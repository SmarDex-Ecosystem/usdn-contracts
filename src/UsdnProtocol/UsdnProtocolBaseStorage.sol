// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { LibBitmap } from "solady/src/utils/LibBitmap.sol";

import { IUsdn } from "src/interfaces/Usdn/IUsdn.sol";
import { IUsdnProtocolErrors } from "src/interfaces/UsdnProtocol/IUsdnProtocolErrors.sol";
import { ILiquidationRewardsManager } from "src/interfaces/OracleMiddleware/ILiquidationRewardsManager.sol";
import { IOracleMiddleware } from "src/interfaces/OracleMiddleware/IOracleMiddleware.sol";
import { Position } from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import { PendingAction, TickData } from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import { DoubleEndedQueue } from "src/libraries/DoubleEndedQueue.sol";
import { HugeUint } from "src/libraries/HugeUint.sol";

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
    address DEAD_ADDRESS;
    uint256 MIN_USDN_SUPPLY;
    uint256 MAX_ACTIONABLE_PENDING_ACTIONS;
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
    uint16 _vaultFeeBps;
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

contract UsdnProtocolBaseStorage is IUsdnProtocolErrors {
    using LibBitmap for LibBitmap.Bitmap;
    using DoubleEndedQueue for DoubleEndedQueue.Deque;

    Storage internal s;

    /**
     * @notice Constructor.
     * @param usdn The USDN ERC20 contract.
     * @param sdex The SDEX ERC20 contract.
     * @param asset The asset ERC20 contract (wstETH).
     * @param oracleMiddleware The oracle middleware contract.
     * @param liquidationRewardsManager The liquidation rewards manager contract.
     * @param tickSpacing The positions tick spacing.
     * @param feeCollector The address of the fee collector.
     */
    constructor(
        IUsdn usdn,
        IERC20Metadata sdex,
        IERC20Metadata asset,
        IOracleMiddleware oracleMiddleware,
        ILiquidationRewardsManager liquidationRewardsManager,
        int24 tickSpacing,
        address feeCollector
    ) {
        // constants
        s.LEVERAGE_DECIMALS = 21;
        s.FUNDING_RATE_DECIMALS = 18;
        s.TOKENS_DECIMALS = 18;
        s.LIQUIDATION_MULTIPLIER_DECIMALS = 38;
        s.FUNDING_SF_DECIMALS = 3;
        s.SDEX_BURN_ON_DEPOSIT_DIVISOR = 1e8;
        s.BPS_DIVISOR = 10_000;
        s.MAX_LIQUIDATION_ITERATION = 10;
        s.DEAD_ADDRESS = address(0xdead);
        s.MIN_USDN_SUPPLY = 1000;
        s.MAX_ACTIONABLE_PENDING_ACTIONS = 20;

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
        s._vaultFeeBps = 4; // 0.04%
        s._sdexBurnOnDepositRatio = 1e6; // 1%
        s._securityDepositValue = 0.5 ether;
        s._usdnRebaseInterval = 0;
        // Long positions
        s._EMA = int256(3 * 10 ** (s.FUNDING_RATE_DECIMALS - 4));

        // Since all USDN must be minted by the protocol, we check that the total supply is 0
        if (usdn.totalSupply() != 0) {
            revert UsdnProtocolInvalidUsdn(address(usdn));
        }
        if (feeCollector == address(0)) {
            revert UsdnProtocolInvalidFeeCollector();
        }

        s._usdn = usdn;
        s._sdex = sdex;
        // Those tokens should have 18 decimals
        if (usdn.decimals() != s.TOKENS_DECIMALS || sdex.decimals() != s.TOKENS_DECIMALS) {
            revert UsdnProtocolInvalidTokenDecimals();
        }

        s._usdnMinDivisor = usdn.MIN_DIVISOR();
        s._asset = asset;
        s._assetDecimals = asset.decimals();
        if (s._assetDecimals < s.FUNDING_SF_DECIMALS) {
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

    function DEAD_ADDRESS() external view returns (address) {
        return s.DEAD_ADDRESS;
    }

    function MIN_USDN_SUPPLY() external view returns (uint256) {
        return s.MIN_USDN_SUPPLY;
    }

    function BPS_DIVISOR() external view returns (uint256) {
        return s.BPS_DIVISOR;
    }

    function SDEX_BURN_ON_DEPOSIT_DIVISOR() external view returns (uint256) {
        return s.SDEX_BURN_ON_DEPOSIT_DIVISOR;
    }

    function LEVERAGE_DECIMALS() external view returns (uint8) {
        return s.LEVERAGE_DECIMALS;
    }

    function MAX_LIQUIDATION_ITERATION() external view returns (uint16) {
        return s.MAX_LIQUIDATION_ITERATION;
    }

    function FUNDING_SF_DECIMALS() external view returns (uint8) {
        return s.FUNDING_SF_DECIMALS;
    }

    function FUNDING_RATE_DECIMALS() external view returns (uint8) {
        return s.FUNDING_RATE_DECIMALS;
    }

    function TOKENS_DECIMALS() external view returns (uint8) {
        return s.TOKENS_DECIMALS;
    }

    function LIQUIDATION_MULTIPLIER_DECIMALS() external view returns (uint8) {
        return s.LIQUIDATION_MULTIPLIER_DECIMALS;
    }

    /* -------------------------------------------------------------------------- */
    /*                                 Immutables getters                         */
    /* -------------------------------------------------------------------------- */

    function getTickSpacing() external view returns (int24) {
        return s._tickSpacing;
    }

    function getAsset() external view returns (IERC20Metadata) {
        return s._asset;
    }

    function getSdex() external view returns (IERC20Metadata) {
        return s._sdex;
    }

    function getPriceFeedDecimals() external view returns (uint8) {
        return s._priceFeedDecimals;
    }

    function getAssetDecimals() external view returns (uint8) {
        return s._assetDecimals;
    }

    function getUsdn() external view returns (IUsdn) {
        return s._usdn;
    }

    function getUsdnMinDivisor() external view returns (uint256) {
        return s._usdnMinDivisor;
    }

    /* -------------------------------------------------------------------------- */
    /*                                 Parameters getters                         */
    /* -------------------------------------------------------------------------- */

    function getOracleMiddleware() external view returns (IOracleMiddleware) {
        return s._oracleMiddleware;
    }

    function getLiquidationRewardsManager() external view returns (ILiquidationRewardsManager) {
        return s._liquidationRewardsManager;
    }

    function getMinLeverage() external view returns (uint256) {
        return s._minLeverage;
    }

    function getMaxLeverage() external view returns (uint256) {
        return s._maxLeverage;
    }

    function getValidationDeadline() external view returns (uint256) {
        return s._validationDeadline;
    }

    function getLiquidationPenalty() external view returns (uint8) {
        return s._liquidationPenalty;
    }

    function getSafetyMarginBps() external view returns (uint256) {
        return s._safetyMarginBps;
    }

    function getLiquidationIteration() external view returns (uint16) {
        return s._liquidationIteration;
    }

    function getEMAPeriod() external view returns (uint128) {
        return s._EMAPeriod;
    }

    function getFundingSF() external view returns (uint256) {
        return s._fundingSF;
    }

    function getProtocolFeeBps() external view returns (uint16) {
        return s._protocolFeeBps;
    }

    function getPositionFeeBps() external view returns (uint16) {
        return s._positionFeeBps;
    }

    function getVaultFeeBps() external view returns (uint16) {
        return s._vaultFeeBps;
    }

    function getSdexBurnOnDepositRatio() external view returns (uint32) {
        return s._sdexBurnOnDepositRatio;
    }

    function getSecurityDepositValue() external view returns (uint64) {
        return s._securityDepositValue;
    }

    function getFeeThreshold() external view returns (uint256) {
        return s._feeThreshold;
    }

    function getFeeCollector() external view returns (address) {
        return s._feeCollector;
    }

    function getMiddlewareValidationDelay() external view returns (uint256) {
        return s._oracleMiddleware.getValidationDelay();
    }

    function getTargetUsdnPrice() external view returns (uint128) {
        return s._targetUsdnPrice;
    }

    function getUsdnRebaseThreshold() external view returns (uint128) {
        return s._usdnRebaseThreshold;
    }

    function getUsdnRebaseInterval() external view returns (uint256) {
        return s._usdnRebaseInterval;
    }

    function getMinLongPosition() external view returns (uint256) {
        return s._minLongPosition;
    }

    /* -------------------------------------------------------------------------- */
    /*                                    State getters                           */
    /* -------------------------------------------------------------------------- */

    function getLastFunding() external view returns (int256) {
        return s._lastFunding;
    }

    function getLastPrice() external view returns (uint128) {
        return s._lastPrice;
    }

    function getLastUpdateTimestamp() external view returns (uint128) {
        return s._lastUpdateTimestamp;
    }

    function getPendingProtocolFee() external view returns (uint256) {
        return s._pendingProtocolFee;
    }

    function getPendingAction(address user) external view returns (uint256) {
        return s._pendingActions[user];
    }

    function getPendingActionAt(uint256 index) external view returns (PendingAction memory action_) {
        // slither-disable-next-line unused-return
        (action_,) = s._pendingActionsQueue.at(index);
    }

    function getBalanceVault() external view returns (uint256) {
        return s._balanceVault;
    }

    function getLastRebaseCheck() external view returns (uint256) {
        return s._lastRebaseCheck;
    }

    function getEMA() external view returns (int256) {
        return s._EMA;
    }

    function getBalanceLong() external view returns (uint256) {
        return s._balanceLong;
    }

    function getTotalExpo() external view returns (uint256) {
        return s._totalExpo;
    }

    function getLiqMultiplierAccumulator() external view returns (HugeUint.Uint512 memory) {
        return s._liqMultiplierAccumulator;
    }

    function getTickVersion(int24 tick) external view returns (uint256) {
        return s._tickVersion[tick];
    }

    function getTickData(int24 tick) external view returns (TickData memory) {
        bytes32 cachedTickHash = tickHash(tick, s._tickVersion[tick]);
        return s._tickData[cachedTickHash];
    }

    function getCurrentLongPosition(int24 tick, uint256 index) external view returns (Position memory) {
        uint256 version = s._tickVersion[tick];
        bytes32 cachedTickHash = tickHash(tick, version);
        return s._longPositions[cachedTickHash][index];
    }

    function getHighestPopulatedTick() external view returns (int24) {
        return s._highestPopulatedTick;
    }

    function getTotalLongPositions() external view returns (uint256) {
        return s._totalLongPositions;
    }

    function tickHash(int24 tick, uint256 version) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(tick, version));
    }

    function getExpoImbalanceLimits()
        external
        view
        returns (
            int256 openExpoImbalanceLimitBps_,
            int256 depositExpoImbalanceLimitBps_,
            int256 withdrawalExpoImbalanceLimitBps_,
            int256 closeExpoImbalanceLimitBps_
        )
    {
        return (
            s._openExpoImbalanceLimitBps,
            s._depositExpoImbalanceLimitBps,
            s._withdrawalExpoImbalanceLimitBps,
            s._closeExpoImbalanceLimitBps
        );
    }
}

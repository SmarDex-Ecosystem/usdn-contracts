// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { LibBitmap } from "solady/src/utils/LibBitmap.sol";

import { IUsdnProtocolStorage } from "src/interfaces/UsdnProtocol/IUsdnProtocolStorage.sol";
import { InitializableReentrancyGuard } from "src/utils/InitializableReentrancyGuard.sol";
import { IUsdn } from "src/interfaces/Usdn/IUsdn.sol";
import { ILiquidationRewardsManager } from "src/interfaces/OracleMiddleware/ILiquidationRewardsManager.sol";
import { IOracleMiddleware } from "src/interfaces/OracleMiddleware/IOracleMiddleware.sol";
import { IRebalancer } from "src/interfaces/Rebalancer/IRebalancer.sol";
import { Position } from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import { PendingAction, TickData } from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import { DoubleEndedQueue } from "src/libraries/DoubleEndedQueue.sol";
import { HugeUint } from "src/libraries/HugeUint.sol";

abstract contract UsdnProtocolStorage is IUsdnProtocolStorage, InitializableReentrancyGuard {
    using LibBitmap for LibBitmap.Bitmap;
    using DoubleEndedQueue for DoubleEndedQueue.Deque;

    /* -------------------------------------------------------------------------- */
    /*                                  Constants                                 */
    /* -------------------------------------------------------------------------- */

    /// @inheritdoc IUsdnProtocolStorage
    uint8 public constant LEVERAGE_DECIMALS = 21;

    /// @inheritdoc IUsdnProtocolStorage
    uint8 public constant FUNDING_RATE_DECIMALS = 18;

    /// @inheritdoc IUsdnProtocolStorage
    uint8 public constant TOKENS_DECIMALS = 18;

    /// @inheritdoc IUsdnProtocolStorage
    uint8 public constant LIQUIDATION_MULTIPLIER_DECIMALS = 38;

    /// @inheritdoc IUsdnProtocolStorage
    uint8 public constant FUNDING_SF_DECIMALS = 3;

    /// @inheritdoc IUsdnProtocolStorage
    uint256 public constant SDEX_BURN_ON_DEPOSIT_DIVISOR = 1e8;

    /// @inheritdoc IUsdnProtocolStorage
    uint256 public constant BPS_DIVISOR = 10_000;

    /// @inheritdoc IUsdnProtocolStorage
    uint16 public constant MAX_LIQUIDATION_ITERATION = 10;

    /// @inheritdoc IUsdnProtocolStorage
    int24 public constant NO_POSITION_TICK = type(int24).min;

    /* -------------------------------------------------------------------------- */
    /*                                 Immutables                                 */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice The liquidation tick spacing for storing long positions.
     * @dev A tick spacing of 1 is equivalent to a 0.1% increase in liquidation price between ticks. A tick spacing of
     * 10 is equivalent to a 1% increase in liquidation price between ticks.
     */
    int24 internal immutable _tickSpacing;

    /// @notice The asset ERC20 contract (wstETH).
    IERC20Metadata internal immutable _asset;

    /// @notice The asset decimals (wstETH => 18).
    uint8 internal immutable _assetDecimals;

    /// @notice The price feed decimals (middleware => 18).
    uint8 internal immutable _priceFeedDecimals;

    /// @notice The USDN ERC20 contract.
    IUsdn internal immutable _usdn;

    /// @notice The SDEX ERC20 contract.
    IERC20Metadata internal immutable _sdex;

    /// @notice The MIN_DIVISOR constant of the USDN token.
    uint256 internal immutable _usdnMinDivisor;

    /* -------------------------------------------------------------------------- */
    /*                                 Parameters                                 */
    /* -------------------------------------------------------------------------- */

    /// @notice The oracle middleware contract.
    IOracleMiddleware internal _oracleMiddleware;

    /// @notice The liquidation rewards manager contract.
    ILiquidationRewardsManager internal _liquidationRewardsManager;

    /// @notice The rebalancer contract.
    IRebalancer internal _rebalancer;

    /// @notice The minimum leverage for a position (1.000000001)
    uint256 internal _minLeverage = 10 ** LEVERAGE_DECIMALS + 10 ** 12;

    /// @notice The maximum leverage for a position
    uint256 internal _maxLeverage = 10 * 10 ** LEVERAGE_DECIMALS;

    /// @notice The deadline for a user to confirm their own action
    uint256 internal _validationDeadline = 20 minutes;

    /// @notice Safety margin for the liquidation price of newly open positions, in basis points
    uint256 internal _safetyMarginBps = 200; // 2%

    /// @notice User current liquidation iteration in tick.
    uint16 internal _liquidationIteration = 1;

    /// @notice The protocol fee percentage (in bps)
    uint16 internal _protocolFeeBps = 10;

    /**
     * @notice Part of the remaining collateral that is given as bonus to the Rebalancer upon liquidation of a tick,
     * in basis points
     * @dev The rest is sent to the Vault balance
     */
    uint16 internal _rebalancerBonusBps = 8000; // 80%

    /// @notice The liquidation penalty (in tick spacing units)
    uint8 internal _liquidationPenalty = 2; // 200 ticks -> ~2.02%

    /// @notice The moving average period of the funding rate
    uint128 internal _EMAPeriod = 5 days;

    /// @notice The scaling factor (SF) of the funding rate (0.12)
    uint256 internal _fundingSF = 12 * 10 ** (FUNDING_SF_DECIMALS - 2);

    /// @notice The fee threshold above which fee will be sent
    uint256 internal _feeThreshold = 1 ether;

    /**
     * @notice The imbalance limit of the long expo for open actions (in basis points).
     * @dev As soon as the difference between vault expo and long expo exceeds this basis point limit in favor of long
     * the open rebalancing mechanism is triggered, preventing the opening of a new long position.
     */
    int256 internal _openExpoImbalanceLimitBps = 200;

    /**
     * @notice The imbalance limit of the long expo for withdrawal actions (in basis points).
     * @dev As soon as the difference between vault expo and long expo exceeds this basis point limit in favor of long,
     * the withdrawal rebalancing mechanism is triggered, preventing the withdraw of existing vault position.
     */
    int256 internal _withdrawalExpoImbalanceLimitBps = 600;

    /**
     * @notice The imbalance limit of the vault expo for deposit actions (in basis points).
     * @dev As soon as the difference between vault expo and long expo exceeds this basis point limit in favor of vault,
     * the deposit vault rebalancing mechanism is triggered, preventing the opening of new vault position.
     */
    int256 internal _depositExpoImbalanceLimitBps = 200;

    /**
     * @notice The imbalance limit of the vault expo for close actions (in basis points).
     * @dev As soon as the difference between vault expo and long expo exceeds this basis point limit in favor of vault,
     * the withdrawal vault rebalancing mechanism is triggered, preventing the close of existing long position.
     */
    int256 internal _closeExpoImbalanceLimitBps = 600;

    /**
     * @notice The target imbalance on the long side (in basis points)
     * @dev This value will be used to calculate how much of the missing trading expo
     * the rebalancer position will try to compensate
     */
    int256 internal _longImbalanceTargetBps = 300;

    /// @notice The position fee in basis points
    uint16 internal _positionFeeBps = 4; // 0.04%

    /// @notice The fee for vault deposits and withdrawals, in basis points
    uint16 internal _vaultFeeBps = 4; // 0.04%

    /// @notice The ratio of USDN to SDEX tokens to burn on deposit
    uint32 internal _sdexBurnOnDepositRatio = 1e6; // 1%

    /// @notice The fee collector's address
    address internal _feeCollector;

    /// @notice The deposit required for a new position (0.5 ether)
    uint64 internal _securityDepositValue = 0.5 ether;

    /// @notice The nominal (target) price of USDN (with _priceFeedDecimals)
    uint128 internal _targetUsdnPrice;

    /// @notice The USDN price threshold to trigger a rebase (with _priceFeedDecimals)
    uint128 internal _usdnRebaseThreshold;

    /**
     * @notice The interval between two automatic rebase checks. Disabled by default.
     * @dev A rebase can be forced (if the `_usdnRebaseThreshold` is exceeded) by calling the `liquidate` function
     */
    uint256 internal _usdnRebaseInterval = 0;

    /// @notice The minimum long position size (with _assetDecimals)
    uint256 internal _minLongPosition;

    /* -------------------------------------------------------------------------- */
    /*                                    State                                   */
    /* -------------------------------------------------------------------------- */

    /// @notice The funding corresponding to the last update timestamp
    int256 internal _lastFunding;

    /// @notice The price of the asset during the last balances update (with price feed decimals)
    uint128 internal _lastPrice;

    /// @notice The timestamp of the last balances update
    uint128 internal _lastUpdateTimestamp;

    /// @notice The pending protocol fee accumulator
    uint256 internal _pendingProtocolFee;

    /* -------------------------- Pending actions queue ------------------------- */

    /**
     * @notice The pending actions by user (1 per user max).
     * @dev The value stored is an index into the `pendingActionsQueue` deque, shifted by one. A value of 0 means no
     * pending action. Since the deque uses uint128 indices, the highest index will not overflow when adding one.
     */
    mapping(address => uint256) internal _pendingActions;

    /// @notice The pending actions queue.
    DoubleEndedQueue.Deque internal _pendingActionsQueue;

    /* ---------------------------------- Vault --------------------------------- */

    /// @notice The balance of deposits (with asset decimals)
    uint256 internal _balanceVault;

    /// @notice The timestamp when the last USDN rebase check was performed
    uint256 internal _lastRebaseCheck;

    /* ----------------------------- Long positions ----------------------------- */

    /// @notice The exponential moving average of the funding (0.0003 at initialization)
    int256 internal _EMA = int256(3 * 10 ** (FUNDING_RATE_DECIMALS - 4));

    /// @notice The balance of long positions (with asset decimals)
    uint256 internal _balanceLong;

    /// @notice The total exposure (with asset decimals)
    uint256 internal _totalExpo;

    /*
     * @notice The accumulator used to calculate the liquidation multiplier
     * @dev This is the sum, for all ticks, of the total expo of positions inside the tick, multiplied by the
     * unadjusted price of the tick which is `_tickData[tickHash].liquidationPenalty * _tickSpacing` below.
     * The unadjusted price is obtained with `TickMath.getPriceAtTick`.
     */
    HugeUint.Uint512 internal _liqMultiplierAccumulator;

    /// @notice The liquidation tick version.
    mapping(int24 => uint256) internal _tickVersion;

    /// @notice The long positions per versioned tick (liquidation price)
    mapping(bytes32 => Position[]) internal _longPositions;

    /// @notice Accumulated data for a given tick and tick version
    mapping(bytes32 => TickData) internal _tickData;

    /// @notice The highest tick with a position
    int24 internal _highestPopulatedTick;

    /// @notice Cache of the total long positions count
    uint256 internal _totalLongPositions;

    /// @notice The bitmap used to quickly find populated ticks
    LibBitmap.Bitmap internal _tickBitmap;

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
        // Since all USDN must be minted by the protocol, we check that the total supply is 0
        if (usdn.totalSupply() != 0) {
            revert UsdnProtocolInvalidUsdn(address(usdn));
        }
        if (feeCollector == address(0)) {
            revert UsdnProtocolInvalidFeeCollector();
        }

        _usdn = usdn;
        _sdex = sdex;
        // Those tokens should have 18 decimals
        if (usdn.decimals() != TOKENS_DECIMALS || sdex.decimals() != TOKENS_DECIMALS) {
            revert UsdnProtocolInvalidTokenDecimals();
        }

        _usdnMinDivisor = usdn.MIN_DIVISOR();
        _asset = asset;
        _assetDecimals = asset.decimals();
        if (_assetDecimals < FUNDING_SF_DECIMALS) {
            revert UsdnProtocolInvalidAssetDecimals(_assetDecimals);
        }
        _oracleMiddleware = oracleMiddleware;
        _priceFeedDecimals = oracleMiddleware.getDecimals();
        _liquidationRewardsManager = liquidationRewardsManager;
        _tickSpacing = tickSpacing;
        _feeCollector = feeCollector;

        _targetUsdnPrice = uint128(10_087 * 10 ** (_priceFeedDecimals - 4)); // $1.0087
        _usdnRebaseThreshold = uint128(1009 * 10 ** (_priceFeedDecimals - 3)); // $1.009
        _minLongPosition = 2 * 10 ** _assetDecimals;
    }

    /* -------------------------------------------------------------------------- */
    /*                                 Immutables getters                         */
    /* -------------------------------------------------------------------------- */

    /// @inheritdoc IUsdnProtocolStorage
    function getTickSpacing() external view returns (int24) {
        return _tickSpacing;
    }

    /// @inheritdoc IUsdnProtocolStorage
    function getAsset() external view returns (IERC20Metadata) {
        return _asset;
    }

    /// @inheritdoc IUsdnProtocolStorage
    function getSdex() external view returns (IERC20Metadata) {
        return _sdex;
    }

    /// @inheritdoc IUsdnProtocolStorage
    function getPriceFeedDecimals() external view returns (uint8) {
        return _priceFeedDecimals;
    }

    /// @inheritdoc IUsdnProtocolStorage
    function getAssetDecimals() external view returns (uint8) {
        return _assetDecimals;
    }

    /// @inheritdoc IUsdnProtocolStorage
    function getUsdn() external view returns (IUsdn) {
        return _usdn;
    }

    /// @inheritdoc IUsdnProtocolStorage
    function getUsdnMinDivisor() external view returns (uint256) {
        return _usdnMinDivisor;
    }

    /* -------------------------------------------------------------------------- */
    /*                                 Parameters getters                         */
    /* -------------------------------------------------------------------------- */

    /// @inheritdoc IUsdnProtocolStorage
    function getOracleMiddleware() external view returns (IOracleMiddleware) {
        return _oracleMiddleware;
    }

    /// @inheritdoc IUsdnProtocolStorage
    function getLiquidationRewardsManager() external view returns (ILiquidationRewardsManager) {
        return _liquidationRewardsManager;
    }

    /// @inheritdoc IUsdnProtocolStorage
    function getRebalancer() external view returns (IRebalancer) {
        return _rebalancer;
    }

    /// @inheritdoc IUsdnProtocolStorage
    function getMinLeverage() external view returns (uint256) {
        return _minLeverage;
    }

    /// @inheritdoc IUsdnProtocolStorage
    function getMaxLeverage() external view returns (uint256) {
        return _maxLeverage;
    }

    /// @inheritdoc IUsdnProtocolStorage
    function getValidationDeadline() external view returns (uint256) {
        return _validationDeadline;
    }

    /// @inheritdoc IUsdnProtocolStorage
    function getLiquidationPenalty() external view returns (uint8) {
        return _liquidationPenalty;
    }

    /// @inheritdoc IUsdnProtocolStorage
    function getSafetyMarginBps() external view returns (uint256) {
        return _safetyMarginBps;
    }

    /// @inheritdoc IUsdnProtocolStorage
    function getLiquidationIteration() external view returns (uint16) {
        return _liquidationIteration;
    }

    /// @inheritdoc IUsdnProtocolStorage
    function getEMAPeriod() external view returns (uint128) {
        return _EMAPeriod;
    }

    /// @inheritdoc IUsdnProtocolStorage
    function getFundingSF() external view returns (uint256) {
        return _fundingSF;
    }

    /// @inheritdoc IUsdnProtocolStorage
    function getProtocolFeeBps() external view returns (uint16) {
        return _protocolFeeBps;
    }

    /// @inheritdoc IUsdnProtocolStorage
    function getPositionFeeBps() external view returns (uint16) {
        return _positionFeeBps;
    }

    /// @inheritdoc IUsdnProtocolStorage
    function getVaultFeeBps() external view returns (uint16) {
        return _vaultFeeBps;
    }

    /// @inheritdoc IUsdnProtocolStorage
    function getRebalancerBonusBps() external view returns (uint16) {
        return _rebalancerBonusBps;
    }

    /// @inheritdoc IUsdnProtocolStorage
    function getSdexBurnOnDepositRatio() external view returns (uint32) {
        return _sdexBurnOnDepositRatio;
    }

    /// @inheritdoc IUsdnProtocolStorage
    function getSecurityDepositValue() external view returns (uint64) {
        return _securityDepositValue;
    }

    /// @inheritdoc IUsdnProtocolStorage
    function getFeeThreshold() external view returns (uint256) {
        return _feeThreshold;
    }

    /// @inheritdoc IUsdnProtocolStorage
    function getFeeCollector() external view returns (address) {
        return _feeCollector;
    }

    /// @inheritdoc IUsdnProtocolStorage
    function getMiddlewareValidationDelay() external view returns (uint256) {
        return _oracleMiddleware.getValidationDelay();
    }

    /// @inheritdoc IUsdnProtocolStorage
    function getTargetUsdnPrice() external view returns (uint128) {
        return _targetUsdnPrice;
    }

    /// @inheritdoc IUsdnProtocolStorage
    function getUsdnRebaseThreshold() external view returns (uint128) {
        return _usdnRebaseThreshold;
    }

    /// @inheritdoc IUsdnProtocolStorage
    function getUsdnRebaseInterval() external view returns (uint256) {
        return _usdnRebaseInterval;
    }

    /// @inheritdoc IUsdnProtocolStorage
    function getMinLongPosition() external view returns (uint256) {
        return _minLongPosition;
    }

    /* -------------------------------------------------------------------------- */
    /*                                    State getters                           */
    /* -------------------------------------------------------------------------- */

    /// @inheritdoc IUsdnProtocolStorage
    function getLastFunding() external view returns (int256) {
        return _lastFunding;
    }

    /// @inheritdoc IUsdnProtocolStorage
    function getLastPrice() external view returns (uint128) {
        return _lastPrice;
    }

    /// @inheritdoc IUsdnProtocolStorage
    function getLastUpdateTimestamp() external view returns (uint128) {
        return _lastUpdateTimestamp;
    }

    /// @inheritdoc IUsdnProtocolStorage
    function getPendingProtocolFee() external view returns (uint256) {
        return _pendingProtocolFee;
    }

    /// @inheritdoc IUsdnProtocolStorage
    function getPendingAction(address user) external view returns (uint256) {
        return _pendingActions[user];
    }

    /// @inheritdoc IUsdnProtocolStorage
    function getPendingActionAt(uint256 index) external view returns (PendingAction memory action_) {
        // slither-disable-next-line unused-return
        (action_,) = _pendingActionsQueue.at(index);
    }

    /// @inheritdoc IUsdnProtocolStorage
    function getBalanceVault() external view returns (uint256) {
        return _balanceVault;
    }

    /// @inheritdoc IUsdnProtocolStorage
    function getLastRebaseCheck() external view returns (uint256) {
        return _lastRebaseCheck;
    }

    /// @inheritdoc IUsdnProtocolStorage
    function getEMA() external view returns (int256) {
        return _EMA;
    }

    /// @inheritdoc IUsdnProtocolStorage
    function getBalanceLong() external view returns (uint256) {
        return _balanceLong;
    }

    /// @inheritdoc IUsdnProtocolStorage
    function getTotalExpo() external view returns (uint256) {
        return _totalExpo;
    }

    /// @inheritdoc IUsdnProtocolStorage
    function getLiqMultiplierAccumulator() external view returns (HugeUint.Uint512 memory) {
        return _liqMultiplierAccumulator;
    }

    /// @inheritdoc IUsdnProtocolStorage
    function getTickVersion(int24 tick) external view returns (uint256) {
        return _tickVersion[tick];
    }

    /// @inheritdoc IUsdnProtocolStorage
    function getTickData(int24 tick) external view returns (TickData memory) {
        bytes32 cachedTickHash = tickHash(tick, _tickVersion[tick]);
        return _tickData[cachedTickHash];
    }

    /// @inheritdoc IUsdnProtocolStorage
    function getCurrentLongPosition(int24 tick, uint256 index) external view returns (Position memory) {
        uint256 version = _tickVersion[tick];
        bytes32 cachedTickHash = tickHash(tick, version);
        return _longPositions[cachedTickHash][index];
    }

    /// @inheritdoc IUsdnProtocolStorage
    function getHighestPopulatedTick() external view returns (int24) {
        return _highestPopulatedTick;
    }

    /// @inheritdoc IUsdnProtocolStorage
    function getTotalLongPositions() external view returns (uint256) {
        return _totalLongPositions;
    }

    /// @inheritdoc IUsdnProtocolStorage
    function tickHash(int24 tick, uint256 version) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(tick, version));
    }

    /// @inheritdoc IUsdnProtocolStorage
    function getDepositExpoImbalanceLimitBps() external view returns (int256 depositExpoImbalanceLimitBps_) {
        depositExpoImbalanceLimitBps_ = _depositExpoImbalanceLimitBps;
    }

    /// @inheritdoc IUsdnProtocolStorage
    function getWithdrawalExpoImbalanceLimitBps() external view returns (int256 withdrawalExpoImbalanceLimitBps_) {
        withdrawalExpoImbalanceLimitBps_ = _withdrawalExpoImbalanceLimitBps;
    }

    /// @inheritdoc IUsdnProtocolStorage
    function getOpenExpoImbalanceLimitBps() external view returns (int256 openExpoImbalanceLimitBps_) {
        openExpoImbalanceLimitBps_ = _openExpoImbalanceLimitBps;
    }

    /// @inheritdoc IUsdnProtocolStorage
    function getCloseExpoImbalanceLimitBps() external view returns (int256 closeExpoImbalanceLimitBps_) {
        closeExpoImbalanceLimitBps_ = _closeExpoImbalanceLimitBps;
    }

    /// @inheritdoc IUsdnProtocolStorage
    function getLongImbalanceTargetBps() external view returns (int256 longImbalanceTargetBps_) {
        longImbalanceTargetBps_ = _longImbalanceTargetBps;
    }
}

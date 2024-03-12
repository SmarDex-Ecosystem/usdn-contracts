// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { LibBitmap } from "solady/src/utils/LibBitmap.sol";

import { IUsdnProtocolStorage } from "src/interfaces/UsdnProtocol/IUsdnProtocolStorage.sol";
import { InitializableReentrancyGuard } from "src/utils/InitializableReentrancyGuard.sol";
import { IUsdn } from "src/interfaces/Usdn/IUsdn.sol";
import { ILiquidationRewardsManager } from "src/interfaces/OracleMiddleware/ILiquidationRewardsManager.sol";
import { IOracleMiddleware } from "src/interfaces/OracleMiddleware/IOracleMiddleware.sol";
import { Position } from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import { PendingAction } from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import { DoubleEndedQueue } from "src/libraries/DoubleEndedQueue.sol";

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
    uint8 public constant LIQUIDATION_MULTIPLIER_DECIMALS = 38;

    /// @inheritdoc IUsdnProtocolStorage
    uint8 public constant FUNDING_SF_DECIMALS = 3;

    /// @inheritdoc IUsdnProtocolStorage
    uint256 public constant BPS_DIVISOR = 10_000;

    /// @inheritdoc IUsdnProtocolStorage
    uint16 public constant MAX_LIQUIDATION_ITERATION = 10;

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

    /// @notice The decimals of the USDN token.
    uint8 internal immutable _usdnDecimals;

    /* -------------------------------------------------------------------------- */
    /*                                 Parameters                                 */
    /* -------------------------------------------------------------------------- */

    /// @notice The oracle middleware contract.
    IOracleMiddleware internal _oracleMiddleware;

    /// @notice The liquidation rewards manager contract.
    ILiquidationRewardsManager internal _liquidationRewardsManager;

    /// @notice The minimum leverage for a position (1.000000001)
    uint256 internal _minLeverage = 10 ** LEVERAGE_DECIMALS + 10 ** 12;

    /// @notice The maximum leverage for a position
    uint256 internal _maxLeverage = 10 * 10 ** LEVERAGE_DECIMALS;

    /// @notice The deadline for a user to confirm their own action
    uint256 internal _validationDeadline = 20 minutes;

    /// @notice The liquidation penalty (in tick spacing units)
    uint24 internal _liquidationPenalty = 2; // 200 ticks -> ~2.02%

    /// @notice Safety margin for the liquidation price of newly open positions, in basis points
    uint256 internal _safetyMarginBps = 200; // 2%

    /// @notice User current liquidation iteration in tick.
    uint16 internal _liquidationIteration = 3;

    // TODO: Add checks when creating the setter for this variable (!= 0)
    /// @notice The moving average period of the funding rate
    uint128 internal _EMAPeriod = 5 days;

    /// @notice The scaling factor (SF) of the funding rate (0.12)
    uint256 internal _fundingSF = 12 * 10 ** (FUNDING_SF_DECIMALS - 2);

    /// @notice The protocol fee percentage (in bps)
    uint16 internal _protocolFeeBps = 10;

    /// @notice The fee collector's address
    address internal _feeCollector;

    /// @notice The fee threshold above which fee will be sent
    uint256 internal _feeThreshold = 1 ether;

    /// @notice The position fee in basis point
    uint16 internal _positionFeeBps = 4; // 0.04%

    /// @notice The deposit required for a new position
    uint256 internal _securityDepositValue = 0.5 ether;

    /* -------------------------------------------------------------------------- */
    /*                                    State                                   */
    /* -------------------------------------------------------------------------- */

    /// @notice The funding corresponding to the last update timestamp
    int256 internal _lastFunding;

    /// @notice The price of the asset during the last balances update (with price feed decimals)
    uint128 internal _lastPrice;

    /// @notice The timestamp of the last balances update
    uint128 internal _lastUpdateTimestamp;

    /**
     * @notice The multiplier for liquidation price calculations
     * @dev This value represents 1 with 38 decimals to have the same precision when the multiplier
     * tends to 0 and high values (uint256.max have 78 digits).
     */
    uint256 internal _liquidationMultiplier = 1e38;

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

    /* ----------------------------- Long positions ----------------------------- */

    /// @notice The exponential moving average of the funding (0.0003 at initialization)
    int256 internal _EMA = int256(3 * 10 ** (FUNDING_RATE_DECIMALS - 4));

    /// @notice The balance of long positions (with asset decimals)
    uint256 internal _balanceLong;

    /// @notice The total exposure (with asset decimals)
    uint256 internal _totalExpo;

    /// @notice The liquidation tick version.
    mapping(int24 => uint256) internal _tickVersion;

    /// @notice The long positions per versioned tick (liquidation price)
    mapping(bytes32 => Position[]) internal _longPositions;

    /// @notice Cache of the total exposure per versioned tick
    mapping(bytes32 => uint256) internal _totalExpoByTick;

    /// @notice Cache of the number of positions per tick
    mapping(bytes32 => uint256) internal _positionsInTick;

    /// @notice Cached value of the maximum initialized tick
    int24 internal _maxInitializedTick;

    /// @notice Cache of the total long positions count
    uint256 internal _totalLongPositions;

    /// @notice The bitmap used to quickly find populated ticks
    LibBitmap.Bitmap internal _tickBitmap;

    /**
     * @notice Constructor.
     * @param usdn The USDN ERC20 contract.
     * @param asset The asset ERC20 contract (wstETH).
     * @param oracleMiddleware The oracle middleware contract.
     * @param liquidationRewardsManager The liquidation rewards manager contract.
     * @param tickSpacing The positions tick spacing.
     * @param feeCollector The address of the fee collector.
     */
    constructor(
        IUsdn usdn,
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
        _usdnDecimals = usdn.decimals();
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
    function getUsdnDecimals() external view returns (uint8) {
        return _usdnDecimals;
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
    function getLiquidationPenalty() external view returns (uint24) {
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
    function getDepositValue() external view returns (uint256) {
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
    function getLiquidationMultiplier() external view returns (uint256) {
        return _liquidationMultiplier;
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
    function getPendingActionAt(uint256 index) external view returns (PendingAction memory) {
        return _pendingActionsQueue.at(index);
    }

    /// @inheritdoc IUsdnProtocolStorage
    function getBalanceVault() external view returns (uint256) {
        return _balanceVault;
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
    function getTickVersion(int24 tick) external view returns (uint256) {
        return _tickVersion[tick];
    }

    /// @inheritdoc IUsdnProtocolStorage
    function getTotalExpoByTick(int24 tick, uint256 version) external view returns (uint256) {
        bytes32 cachedTickHash = tickHash(tick, version);
        return _totalExpoByTick[cachedTickHash];
    }

    /// @inheritdoc IUsdnProtocolStorage
    function getPositionsInTick(int24 tick, uint256 version) external view returns (uint256) {
        bytes32 cachedTickHash = tickHash(tick, version);
        return _positionsInTick[cachedTickHash];
    }

    /// @inheritdoc IUsdnProtocolStorage
    function getCurrentLongPosition(int24 tick, uint256 index) external view returns (Position memory) {
        uint256 version = _tickVersion[tick];
        bytes32 cachedTickHash = tickHash(tick, version);
        return _longPositions[cachedTickHash][index];
    }

    /// @inheritdoc IUsdnProtocolStorage
    function getCurrentTotalExpoByTick(int24 tick) external view returns (uint256) {
        uint256 version = _tickVersion[tick];
        bytes32 cachedTickHash = tickHash(tick, version);
        return _totalExpoByTick[cachedTickHash];
    }

    /// @inheritdoc IUsdnProtocolStorage
    function getCurrentPositionsInTick(int24 tick) external view returns (uint256) {
        uint256 version = _tickVersion[tick];
        bytes32 cachedTickHash = tickHash(tick, version);
        return _positionsInTick[cachedTickHash];
    }

    /// @inheritdoc IUsdnProtocolStorage
    function getMaxInitializedTick() external view returns (int24) {
        return _maxInitializedTick;
    }

    /// @inheritdoc IUsdnProtocolStorage
    function getTotalLongPositions() external view returns (uint256) {
        return _totalLongPositions;
    }

    /// @inheritdoc IUsdnProtocolStorage
    function tickHash(int24 tick, uint256 version) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(tick, version));
    }
}

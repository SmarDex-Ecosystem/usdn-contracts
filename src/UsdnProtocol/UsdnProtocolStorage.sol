// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { LibBitmap } from "solady/src/utils/LibBitmap.sol";

import { InitializableReentrancyGuard } from "src/utils/InitializableReentrancyGuard.sol";
import { IUsdn } from "src/interfaces/IUsdn.sol";
import { IOracleMiddleware } from "src/interfaces/IOracleMiddleware.sol";
import { IUsdnProtocolErrors, Position, PendingAction } from "src/interfaces/UsdnProtocol/IUsdnProtocol.sol";
import { DoubleEndedQueue } from "src/libraries/DoubleEndedQueue.sol";

abstract contract UsdnProtocolStorage is IUsdnProtocolErrors, InitializableReentrancyGuard {
    using LibBitmap for LibBitmap.Bitmap;

    /* -------------------------------------------------------------------------- */
    /*                                  Constants                                 */
    /* -------------------------------------------------------------------------- */

    /// @notice The number of decimals for leverage values
    uint8 public constant LEVERAGE_DECIMALS = 21;

    /// @notice The number of decimals for funding rate values
    uint8 public constant FUNDING_RATE_DECIMALS = 18;

    /// @notice The number of seconds in a day
    uint256 public constant SECONDS_PER_DAY = 60 * 60 * 24;

    /**
     * @notice Divisor for the percentage values (liquidation penalty, safety margin)
     * @dev Example: 200 -> 2%
     */
    uint256 public constant PERCENTAGE_DIVISOR = 10_000;

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

    /// @notice The minimum leverage for a position
    uint256 internal _minLeverage = 10 ** LEVERAGE_DECIMALS + 1;

    /// @notice The maximum leverage for a position
    uint256 internal _maxLeverage = 10 * 10 ** LEVERAGE_DECIMALS;

    /// @notice The deadline for a user to confirm their own action
    uint256 internal _validationDeadline = 60 minutes;

    /// @notice The funding rate per second
    int256 internal _fundingRatePerSecond = 3_472_222_222; // 18 decimals (0.03% daily -> 0.0000003472% per second)

    /// @notice The liquidation penalty
    uint256 internal _liquidationPenalty = 200; // divisor is 10_000 -> 2%

    /// @notice Safety margin for the liquidation price of newly open positions
    uint256 internal _safetyMargin = 200; // divisor is 10_000 -> 2%

    /* -------------------------------------------------------------------------- */
    /*                                    State                                   */
    /* -------------------------------------------------------------------------- */

    /// @notice The price of the asset during the last balances update (with price feed decimals)
    uint128 internal _lastPrice;

    /// @notice The timestamp of the last balances update
    uint128 internal _lastUpdateTimestamp;

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

    /// @notice The balance of long positions (with asset decimals)
    uint256 internal _balanceLong;

    /// @notice The total exposure (with asset decimals)
    uint256 internal _totalExpo;

    /// @notice The liquidation price tick versions
    // slither-disable-next-line uninitialized-state
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
     * @param tickSpacing_ The positions tick spacing.
     */
    constructor(IUsdn usdn, IERC20Metadata asset, IOracleMiddleware oracleMiddleware, int24 tickSpacing_) {
        // Since all USDN must be minted by the protocol, we check that the total supply is 0
        if (usdn.totalSupply() != 0) {
            revert UsdnProtocolInvalidUsdn(address(usdn));
        }
        _usdn = usdn;
        _usdnDecimals = usdn.decimals();
        _asset = asset;
        _assetDecimals = asset.decimals();
        _oracleMiddleware = oracleMiddleware;
        _priceFeedDecimals = oracleMiddleware.decimals();
        _tickSpacing = tickSpacing_;
    }

    function tickSpacing() external view returns (int24) {
        return _tickSpacing;
    }

    // TODO: add view functions for all storage items that need to be public
}

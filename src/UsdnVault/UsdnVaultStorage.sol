// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

/* -------------------------------------------------------------------------- */
/*                             External libraries                             */
/* -------------------------------------------------------------------------- */

/* --------------------------- External libraries --------------------------- */

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { LibBitmap } from "solady/src/utils/LibBitmap.sol";

/* -------------------------------------------------------------------------- */
/*                              Internal imports                              */
/* -------------------------------------------------------------------------- */

import { Position } from "src/interfaces/UsdnVault/IUsdnVault.sol";
import { IOracleMiddleware } from "src/interfaces/IOracleMiddleware.sol";
import { IUsdn } from "src/interfaces/IUsdn.sol";

contract UsdnVaultStorage {
    // Safe ERC20 and Tick bitmap
    using SafeERC20 for IERC20Metadata;
    using LibBitmap for LibBitmap.Bitmap;

    /* -------------------------------------------------------------------------- */
    /*                                  Constants                                 */
    /* -------------------------------------------------------------------------- */

    /// @notice The number of decimals used in the leverage.
    uint8 public constant LEVERAGE_DECIMALS = 9;
    /// @notice The number of decimals used in the funding rate.
    uint8 public constant FUNDING_RATE_DECIMALS = 18;
    /// @notice The number of seconds in a day.
    uint256 public constant SECONDS_PER_DAY = 60 * 60 * 24;

    /* -------------------------------------------------------------------------- */
    /*                                 Immutables                                 */
    /* -------------------------------------------------------------------------- */

    /// @notice The positions tick spacing.
    int24 public immutable tickSpacing;
    /// @notice The asset ERC20 contract (stETH).
    IERC20Metadata public immutable asset;
    /// @notice The asset decimals (stETH => 18).
    uint8 public immutable assetDecimals;
    /// @notice The price feed decimals.
    uint8 public immutable priceFeedDecimals;

    /* -------------------------------------------------------------------------- */
    /*                                   Storage                                  */
    /* -------------------------------------------------------------------------- */

    /// @notice The USDN ERC20 contract.
    IUsdn public immutable usdn;

    /// @notice The oracle middleware contract.
    IOracleMiddleware public oracleMiddleware;

    /// @notice The minimum leverage.
    uint256 public minLeverage = 1 * 10 ** LEVERAGE_DECIMALS + 1;
    /// @notice The maximum leverage.
    uint256 public maxLeverage = 10 * 10 ** LEVERAGE_DECIMALS;
    /// @notice The maximum leverage.
    uint256 public validationDeadline = 10 minutes;
    /// @notice The funding rate ration per second.
    int256 public fundingRatePerSecond = 3_472_222_222; // 18 decimals (0.03% daily -> 0.0000003472% per second)

    /// @notice The balance of short positions (asset decimals).
    uint256 public balanceShort;
    /// @notice The balance of long positions (asset decimals).
    uint256 public balanceLong;

    /// @notice The total exposure (asset decimals).
    uint256 public totalExpo;
    /// @notice The last price of the asset on last balances update (price feed decimals).
    uint128 public lastPrice;
    /// @notice The last timestamp of balances update.
    uint128 public lastUpdateTimestamp;

    /// @notice The long positions per tick.
    mapping(bytes32 => Position[]) public longPositions;
    /// @notice The pending short position (1 pending per address).
    mapping(address => Position) public pendingShortPositions;
    /// @notice The total exposure per tick.
    mapping(bytes32 => uint256) public totalExpoByTick;
    /// @notice The tick versions.
    mapping(int24 => uint256) public tickVersion;
    /// @notice The number of positions per tick.
    mapping(bytes32 => uint256) public positionsInTick;

    /// @notice The tick bitmap.
    LibBitmap.Bitmap tickBitmap;
    /// @notice The maximum initialized tick.
    int24 public maxInitializedTick;

    /// @notice The total long positions count.
    uint256 public totalLongPositions;

    /// @notice Constructor.
    /// @param _asset The asset ERC20 contract.
    /// @param _oracleMiddleware The oracle middleware contract.
    /// @param _tickSpacing The positions tick spacing.
    constructor(IUsdn _usdn, IERC20Metadata _asset, IOracleMiddleware _oracleMiddleware, int24 _tickSpacing) {
        usdn = _usdn;
        asset = _asset;
        assetDecimals = _asset.decimals();
        oracleMiddleware = _oracleMiddleware;
        priceFeedDecimals = oracleMiddleware.decimals();
        tickSpacing = _tickSpacing;
    }
}

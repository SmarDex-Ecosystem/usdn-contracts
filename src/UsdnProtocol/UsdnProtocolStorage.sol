// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { IUsdn } from "src/interfaces/IUsdn.sol";
import { IOracleMiddleware } from "src/interfaces/IOracleMiddleware.sol";
import { Position, PendingAction } from "src/interfaces/UsdnProtocol/IUsdnProtocol.sol";
import { DoubleEndedQueue } from "src/libraries/DoubleEndedQueue.sol";

abstract contract UsdnProtocolStorage {
    /* ------------------------------- Immutables ------------------------------- */

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

    /* --------------------------------- Storage -------------------------------- */

    /// @notice The oracle middleware contract.
    IOracleMiddleware internal _oracleMiddleware;

    /// @notice The deadline for a user to confirm their own action.
    uint256 internal _validationDeadline = 60 minutes;

    /// @notice The balance of deposits (with `asset` decimals).
    uint256 internal _balanceVault;

    /// @notice The balance of long positions (with `asset` decimals).
    uint256 internal _balanceLong;

    /// @notice The last price of the asset on last balances update (price feed decimals).
    uint128 internal _lastPrice;

    /// @notice The last timestamp of balances update.
    uint128 internal _lastUpdateTimestamp;

    /**
     * @notice The pending actions by user (1 per user max).
     * @dev The value stored is an index into the `pendingActionsQueue` deque, shifted by one. A value of 0 means no
     * pending action. Since the deque uses uint128 indices, the highest index will still fit here when adding one.
     */
    mapping(address => uint256) internal _pendingActions;

    /// @notice The pending actions queue.
    DoubleEndedQueue.Deque internal _pendingActionsQueue;

    /**
     * @notice Constructor.
     * @param usdn The USDN ERC20 contract.
     * @param asset The asset ERC20 contract (wstETH).
     * @param oracleMiddleware The oracle middleware contract.
     * @param tickSpacing The positions tick spacing.
     */
    constructor(IUsdn usdn, IERC20Metadata asset, IOracleMiddleware oracleMiddleware, int24 tickSpacing) {
        _usdn = usdn;
        _usdnDecimals = usdn.decimals();
        _asset = asset;
        _assetDecimals = asset.decimals();
        _oracleMiddleware = oracleMiddleware;
        _priceFeedDecimals = oracleMiddleware.decimals();
        _tickSpacing = tickSpacing;
    }

    // TODO: add view functions for all storage items that need to be public
}

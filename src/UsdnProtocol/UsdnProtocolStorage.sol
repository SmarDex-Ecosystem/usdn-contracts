// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { IUsdn } from "src/interfaces/IUsdn.sol";
import { IOracleMiddleware } from "src/interfaces/IOracleMiddleware.sol";
import { Position, PendingAction } from "src/interfaces/UsdnProtocol/IUsdnProtocol.sol";
import { DoubleEndedQueue } from "src/libraries/Deque.sol";

abstract contract UsdnProtocolStorage {
    /* ------------------------------- Immutables ------------------------------- */

    /**
     * @notice The liquidation tick spacing for storing long positions.
     * @dev A tick spacing of 1 is equivalent to a 0.1% increase in liquidation price between ticks. A tick spacing of
     * 10 is equivalent to a 1% increase in liquidation price between ticks.
     */
    int24 public immutable tickSpacing;

    /// @notice The asset ERC20 contract (wstETH).
    IERC20Metadata public immutable asset;

    /// @notice The asset decimals (wstETH => 18).
    uint8 public immutable assetDecimals;

    /// @notice The price feed decimals (middleware => 18).
    uint8 public immutable priceFeedDecimals;

    /// @notice The USDN ERC20 contract.
    IUsdn public immutable usdn;

    /// @notice The decimals of the USDN token.
    uint8 public immutable usdnDecimals;

    /* --------------------------------- Storage -------------------------------- */

    /// @notice The oracle middleware contract.
    IOracleMiddleware public oracleMiddleware;

    /// @notice The deadline for a user to confirm their own action.
    uint256 public validationDeadline = 60 minutes;

    /// @notice The balance of deposits (with `asset` decimals).
    uint256 public balanceVault;

    /// @notice The last price of the asset on last balances update (price feed decimals).
    uint128 public lastPrice;

    /// @notice The last timestamp of balances update.
    uint128 public lastUpdateTimestamp;

    /**
     * @notice The pending deposit/withdraw actions by user (1 per user max).
     * @dev The value stored is an index into the `pendingActionsQueue` deque (shifted by one). The value 0 means no
     * pending action. Since the deque uses uint128 indices, the highest index will still fit here when adding one.
     */
    mapping(address => uint256) public pendingVaultActions;

    /// @notice The pending actions queue.
    DoubleEndedQueue.Deque public pendingActionsQueue;

    /**
     * @notice Constructor.
     * @param _usdn The USDN ERC20 contract.
     * @param _asset The asset ERC20 contract (wstETH).
     * @param _oracleMiddleware The oracle middleware contract.
     * @param _tickSpacing The positions tick spacing.
     */
    constructor(IUsdn _usdn, IERC20Metadata _asset, IOracleMiddleware _oracleMiddleware, int24 _tickSpacing) {
        usdn = _usdn;
        usdnDecimals = _usdn.decimals();
        asset = _asset;
        assetDecimals = _asset.decimals();
        oracleMiddleware = _oracleMiddleware;
        priceFeedDecimals = oracleMiddleware.decimals();
        tickSpacing = _tickSpacing;
    }
}

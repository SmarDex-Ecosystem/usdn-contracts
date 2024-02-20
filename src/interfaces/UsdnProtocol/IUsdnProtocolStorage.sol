// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import { IOracleMiddleware } from "src/interfaces/OracleMiddleware/IOracleMiddleware.sol";
import { IUsdnProtocolEvents } from "src/interfaces/UsdnProtocol/IUsdnProtocolEvents.sol";
import { IUsdnProtocolErrors } from "src/interfaces/UsdnProtocol/IUsdnProtocolErrors.sol";
import { IUsdn } from "src/interfaces/Usdn/IUsdn.sol";
import { Position } from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";

import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

/**
 * @title IUsdnProtocolStorage
 * @notice Interface for the storage layer of the USDN protocol.
 */
interface IUsdnProtocolStorage is IUsdnProtocolEvents, IUsdnProtocolErrors {
    /// @notice The number of decimals for leverage values
    function LEVERAGE_DECIMALS() external view returns (uint8);

    /// @notice The number of decimals for funding rate values
    function FUNDING_RATE_DECIMALS() external view returns (uint8);

    /// @notice The number of decimals for liquidation multiplier values
    function LIQUIDATION_MULTIPLIER_DECIMALS() external view returns (uint8);

    /// @notice The number of decimals for the scaling factor of the funding rate
    function FUNDING_SF_DECIMALS() external view returns (uint8);

    /**
     * @notice Divisor for the percentage values (safety margin)
     * @dev Example: 200 -> 2%
     */
    function PERCENTAGE_DIVISOR() external view returns (uint256);

    /// @notice The maximum number of liquidations per transaction
    function MAX_LIQUIDATION_ITERATION() external view returns (uint16);

    /**
     * @notice The liquidation tick spacing for storing long positions.
     * @dev A tick spacing of 1 is equivalent to a 0.01% increase in liquidation price between ticks. A tick spacing of
     * 100 is equivalent to a 1% increase in liquidation price between ticks.
     */
    function getTickSpacing() external view returns (int24);

    /// @notice The asset ERC20 contract (wstETH).
    function getAsset() external view returns (IERC20Metadata);

    /// @notice The asset decimals.
    function getAssetDecimals() external view returns (uint8);

    /// @notice The price feed decimals.
    function getPriceFeedDecimals() external view returns (uint8);

    /// @notice The USDN ERC20 contract.
    function getUsdn() external view returns (IUsdn);

    /// @notice The decimals of the USDN token.
    function getUsdnDecimals() external view returns (uint8);

    /// @notice The oracle middleware contract.
    function getOracleMiddleware() external view returns (IOracleMiddleware);

    /// @notice The minimum leverage for a position
    function getMinLeverage() external view returns (uint256);

    /// @notice The maximum leverage value
    function getMaxLeverage() external view returns (uint256);

    /// @notice The deadline for a user to confirm their own action
    function getValidationDeadline() external view returns (uint256);

    /// @notice The liquidation penalty (in tick spacing units)
    function getLiquidationPenalty() external view returns (uint24);

    /// @notice Safety margin for the liquidation price of newly open positions
    function getSafetyMargin() external view returns (uint256);

    /// @notice User current liquidation iteration in tick.
    function getLiquidationIteration() external view returns (uint16);

    /// @notice The moving average period of the funding rate
    function getEMAPeriod() external view returns (uint128);

    /// @notice The scaling factor (SF) of the funding rate
    function getFundingSF() external view returns (uint256);

    /// @notice The funding corresponding to the last update timestamp
    function getLastFunding() external view returns (int256);

    /// @notice The price of the asset during the last balances update (with price feed decimals)
    function getLastPrice() external view returns (uint128);

    /// @notice The timestamp of the last balances update
    function getLastUpdateTimestamp() external view returns (uint128);

    /// @notice The multiplier for liquidation price calculations
    function getLiquidationMultiplier() external view returns (uint256);

    /**
     * @notice The pending action by user (1 per user max).
     * @dev The value stored is an index into the `pendingActionsQueue` deque, shifted by one. A value of 0 means no
     * pending action. Since the deque uses uint128 indices, the highest index will not overflow when adding one.
     * @param user The user address.
     */
    function getPendingAction(address user) external view returns (uint256);

    /// @notice The balance of deposits (with asset decimals)
    function getBalanceVault() external view returns (uint256);

    /// @notice The exponential moving average of the funding
    function getEMA() external view returns (int256);

    /// @notice The balance of long positions (with asset decimals)
    function getBalanceLong() external view returns (uint256);

    /// @notice The total exposure (with asset decimals)
    function getTotalExpo() external view returns (uint256);

    /**
     * @notice The liquidation tick version.
     * @param tick The tick number.
     */
    function getTickVersion(int24 tick) external view returns (uint256);

    /**
     * @notice The long position per versioned tick (liquidation price) by position index
     * @param tickHash The tickHash of the tick.
     * @param index The position index.
     */
    function getLongPositions(bytes32 tickHash, uint256 index) external view returns (Position memory);

    /**
     * @notice Cache of the total exposure per versioned tick.
     * @param tickHash The tickHash of the tick.
     */
    function getTotalExpoByTick(bytes32 tickHash) external view returns (uint256);

    /**
     * @notice Cache of the number of positions per tick.
     * @param tickHash The tickHash of the tick.
     */
    function getPositionsInTick(bytes32 tickHash) external view returns (uint256);

    /// @notice Cached value of the maximum initialized tick
    function getMaxInitializedTick() external view returns (int24);

    /// @notice Cache of the total long positions count
    function getTotalLongPositions() external view returns (uint256);
}

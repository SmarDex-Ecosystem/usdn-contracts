// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.0;

import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { IOracleMiddleware } from "src/interfaces/OracleMiddleware/IOracleMiddleware.sol";
import { IUsdnProtocolEvents } from "src/interfaces/UsdnProtocol/IUsdnProtocolEvents.sol";
import { IUsdnProtocolErrors } from "src/interfaces/UsdnProtocol/IUsdnProtocolErrors.sol";
import { IUsdn } from "src/interfaces/Usdn/IUsdn.sol";
import { Position } from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import { ILiquidationRewardsManager } from "src/interfaces/OracleMiddleware/ILiquidationRewardsManager.sol";
import { PendingAction } from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";

/**
 * @title IUsdnProtocolStorage
 * @notice Interface for the storage layer of the USDN protocol.
 */
interface IUsdnProtocolStorage is IUsdnProtocolEvents, IUsdnProtocolErrors {
    /* -------------------------------------------------------------------------- */
    /*                                  Constants                                 */
    /* -------------------------------------------------------------------------- */

    /// @notice The number of decimals for leverage values
    function LEVERAGE_DECIMALS() external pure returns (uint8);

    /// @notice The number of decimals for funding rate values
    function FUNDING_RATE_DECIMALS() external pure returns (uint8);

    /// @notice The number of decimals for liquidation multiplier values
    function LIQUIDATION_MULTIPLIER_DECIMALS() external pure returns (uint8);

    /// @notice The number of decimals for the scaling factor of the funding rate
    function FUNDING_SF_DECIMALS() external pure returns (uint8);

    /**
     * @notice Divisor for the bps values
     * @dev Example: 200 -> 2%
     */
    function BPS_DIVISOR() external pure returns (uint256);

    /// @notice The maximum number of liquidations per transaction
    function MAX_LIQUIDATION_ITERATION() external pure returns (uint16);

    /* -------------------------------------------------------------------------- */
    /*                                 Immutables getters                         */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice The liquidation tick spacing for storing long positions.
     * @dev A tick spacing of 1 is equivalent to a 0.01% increase in liquidation price between ticks. A tick spacing of
     * 100 is equivalent to a 1% increase in liquidation price between ticks.
     */
    function getTickSpacing() external view returns (int24);

    /// @notice The asset ERC20 contract (wstETH).
    function getAsset() external view returns (IERC20Metadata);

    /// @notice The price feed decimals.
    function getPriceFeedDecimals() external view returns (uint8);

    /// @notice The asset decimals.
    function getAssetDecimals() external view returns (uint8);

    /// @notice The USDN ERC20 contract.
    function getUsdn() external view returns (IUsdn);

    /// @notice The decimals of the USDN token.
    function getUsdnDecimals() external view returns (uint8);

    /// @notice The MIN_DIVISOR constant of the USDN token.
    function getUsdnMinDivisor() external view returns (uint256);

    /* -------------------------------------------------------------------------- */
    /*                                 Parameters getters                         */
    /* -------------------------------------------------------------------------- */

    /// @notice The oracle middleware contract.
    function getOracleMiddleware() external view returns (IOracleMiddleware);

    /// @notice The liquidation rewards manager contract
    function getLiquidationRewardsManager() external view returns (ILiquidationRewardsManager);

    /// @notice The minimum leverage for a position
    function getMinLeverage() external view returns (uint256);

    /// @notice The maximum leverage value
    function getMaxLeverage() external view returns (uint256);

    /// @notice The deadline for a user to confirm their own action
    function getValidationDeadline() external view returns (uint256);

    /// @notice The liquidation penalty (in tick spacing units)
    function getLiquidationPenalty() external view returns (uint24);

    /// @notice Safety margin for the liquidation price of newly open positions
    function getSafetyMarginBps() external view returns (uint256);

    /// @notice User current liquidation iteration in tick.
    function getLiquidationIteration() external view returns (uint16);

    /// @notice The moving average period of the funding rate
    function getEMAPeriod() external view returns (uint128);

    /// @notice The scaling factor (SF) of the funding rate
    function getFundingSF() external view returns (uint256);

    /// @notice The protocol fee in bps
    function getProtocolFeeBps() external view returns (uint16);

    /// @notice The position fee in bps
    function getPositionFeeBps() external view returns (uint16);

    /// @notice The fee threshold before fees are sent to the fee collector
    function getFeeThreshold() external view returns (uint256);

    /// @notice The address of the fee collector
    function getFeeCollector() external view returns (address);

    /// @notice The address of the fee collector
    function getMiddlewareValidationDelay() external view returns (uint256);

    /**
     * @notice Get the open long expo imbalance limit basis point.
     * @dev As soon as the difference between vault expo and long expo exceeds this basis point limit in favor of long
     * the open rebalancing mechanism is triggered, preventing the opening of a new long position.
     */
    function getOpenExpoImbalanceLimitBps() external view returns (int256);

    /**
     * @notice Get the withdrawal long expo imbalance limit basis point.
     * @dev As soon as the difference between vault expo and long expo exceeds this basis point limit in favor of long,
     * the withdrawal rebalancing mechanism is triggered, preventing the withdraw of existing vault position.
     */
    function getWithdrawalExpoImbalanceLimitBps() external view returns (int256);

    /**
     * @notice Get the deposit vault expo imbalance limit basis point.
     * @dev As soon as the difference between vault expo and long expo exceeds this basis point limit in favor of vault,
     * the deposit rebalancing mechanism is triggered, preventing the opening of new vault position.
     */
    function getDepositExpoImbalanceLimitBps() external view returns (int256);

    /**
     * @notice Get the close vault expo imbalance limit basis point.
     * @dev As soon as the difference between vault expo and long expo exceeds this basis point limit in favor of vault,
     * the close rebalancing mechanism is triggered, preventing the close of existing long position.
     */
    function getCloseExpoImbalanceLimitBps() external view returns (int256);

    /// @notice The nominal (target) price of USDN (with _priceFeedDecimals)
    function getTargetUsdnPrice() external view returns (uint128);

    /// @notice The USDN price threshold to trigger a rebase (with _priceFeedDecimals)
    function getUsdnRebaseThreshold() external view returns (uint128);

    /// @notice The interval between two automatic rebase checks
    function getUsdnRebaseInterval() external view returns (uint256);

    /* -------------------------------------------------------------------------- */
    /*                                    State getters                           */
    /* -------------------------------------------------------------------------- */

    /// @notice The funding corresponding to the last update timestamp
    function getLastFunding() external view returns (int256);

    /// @notice The price of the asset during the last balances update (with price feed decimals)
    function getLastPrice() external view returns (uint128);

    /// @notice The timestamp of the last balances update
    function getLastUpdateTimestamp() external view returns (uint128);

    /// @notice The multiplier for liquidation price calculations
    function getLiquidationMultiplier() external view returns (uint256);

    /// @notice The pending fees that are accumulated in the protocol
    function getPendingProtocolFee() external view returns (uint256);

    /**
     * @notice The pending action by user (1 per user max).
     * @dev The value stored is an index into the `pendingActionsQueue` deque, shifted by one. A value of 0 means no
     * pending action. Since the deque uses uint128 indices, the highest index will not overflow when adding one.
     * @param user The user address.
     */
    function getPendingAction(address user) external view returns (uint256);

    /**
     * @notice The pending action at index
     * @param index The pending action index.
     */
    function getPendingActionAt(uint256 index) external view returns (PendingAction memory);

    /// @notice The balance of deposits (with asset decimals)
    function getBalanceVault() external view returns (uint256);

    /// @notice The timestamp when the last USDN rebase check was performed
    function getLastRebaseCheck() external view returns (uint256);

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
     * @notice Total exposure per versioned tick.
     * @param tick The tick number.
     * @param version The tick version.
     */
    function getTotalExpoByTick(int24 tick, uint256 version) external view returns (uint256);

    /**
     * @notice The number of positions per tick.
     * @param tick The tick number.
     * @param version The tick version.
     */
    function getPositionsInTick(int24 tick, uint256 version) external view returns (uint256);

    /**
     * @notice The long position per current tick (liquidation price) by position index
     * @param tick The tick number.
     * @param index The position index.
     */
    function getCurrentLongPosition(int24 tick, uint256 index) external view returns (Position memory);

    /**
     * @notice The total exposure per current tick.
     * @param tick The tick number.
     */
    function getCurrentTotalExpoByTick(int24 tick) external view returns (uint256);

    /**
     * @notice The number of positions per current tick.
     * @param tick The tick number.
     */
    function getCurrentPositionsInTick(int24 tick) external view returns (uint256);

    /// @notice The maximum initialized tick
    function getMaxInitializedTick() external view returns (int24);

    /// @notice Total long positions count
    function getTotalLongPositions() external view returns (uint256);

    /**
     * @notice The tickHash from tick and tickVersion
     * @param tick The tick number.
     * @param version The tick version.
     */
    function tickHash(int24 tick, uint256 version) external pure returns (bytes32);
}

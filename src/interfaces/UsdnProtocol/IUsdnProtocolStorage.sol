// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import { IUsdnProtocolEvents } from "src/interfaces/UsdnProtocol/IUsdnProtocolEvents.sol";
import { IUsdnProtocolErrors } from "src/interfaces/UsdnProtocol/IUsdnProtocolErrors.sol";

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
     * @notice Divisor for the bps values
     * @dev Example: 200 -> 2%
     */
    function BPS_DIVISOR() external view returns (uint256);

    /// @notice The maximum number of liquidations per transaction
    function MAX_LIQUIDATION_ITERATION() external view returns (uint16);

    /// @notice The denominator of expo imbalance limits
    function EXPO_IMBALANCE_LIMIT_DENOMINATOR() external view returns (uint16);

    /**
     * @notice The liquidation tick spacing for storing long positions
     * @dev A tick spacing of 1 is equivalent to a 0.01% increase in liquidation price between ticks. A tick spacing of
     * 100 is equivalent to a 1% increase in liquidation price between ticks.
     */
    function tickSpacing() external view returns (int24);

    /// @notice The minimum leverage value
    function minLeverage() external view returns (uint256);

    /// @notice The maximum leverage value
    function maxLeverage() external view returns (uint256);

    /// @notice The multiplier for liquidation price calculations
    function liquidationMultiplier() external view returns (uint256);

    /// @notice The liquidation rewards manager contract
    function liquidationRewardsManager() external view returns (address);

    /// @notice The pending fees that are accumulated in the protocol
    function pendingProtocolFee() external view returns (uint256);

    /// @notice The fee threshold before fees are sent to the fee collector
    function feeThreshold() external view returns (uint256);

    /// @notice The address of the fee collector
    function feeCollector() external view returns (address);

    /// @notice The protocol fee in bps
    function protocolFeeBps() external view returns (uint16);

    /**
     * @notice Get the soft longExpo imbalance limit.
     * @dev As soon as the difference between vault expo and long expo exceeds this percentage limit in favor of long
     * the soft long rebalancing mechanism is triggered, preventing the opening of a new long position.
     */
    function getSoftLongExpoImbalanceLimit() external view returns (uint16);

    /**
     * @notice Get the hard longExpo imbalance limit.
     * @dev As soon as the difference between vault expo and long expo exceeds this percentage limit in favor of long,
     * the hard long rebalancing mechanism is triggered, preventing the withdraw of existing vault position.
     */
    function getHardLongExpoImbalanceLimit() external view returns (uint16);

    /**
     * @notice Get the soft vaultExpo imbalance limit.
     * @dev As soon as the difference between vault expo and long expo exceeds this percentage limit in favor of vault,
     * the soft vault rebalancing mechanism is triggered, preventing the opening of new vault position.
     */
    function getSoftVaultExpoImbalanceLimit() external view returns (uint16);

    /**
     * @notice Get the hard vaultExpo imbalance limit.
     * @dev As soon as the difference between vault expo and long expo exceeds this percentage limit in favor of vault,
     * the hard vault rebalancing mechanism is triggered, preventing the close of existing long position.
     */
    function getHardVaultExpoImbalanceLimit() external view returns (uint16);
}

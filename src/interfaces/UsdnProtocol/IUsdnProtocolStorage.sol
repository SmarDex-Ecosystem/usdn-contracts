// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.0;

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
}

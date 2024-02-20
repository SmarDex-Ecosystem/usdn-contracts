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

    /// @notice The number of seconds in a day
    function SECONDS_PER_DAY() external view returns (uint256);

    /**
     * @notice Divisor for the percentage values (safety margin)
     * @dev Example: 200 -> 2%
     */
    function PERCENTAGE_DIVISOR() external view returns (uint256);

    /// @notice The maximum number of liquidations per transaction
    function MAX_LIQUIDATION_ITERATION() external view returns (uint16);

    /// @notice The protocol fee denominator
    function PROTOCOL_FEE_DENOMINATOR() external view returns (uint16);

    /// @notice The maximum protocol fee
    function MAX_PROTOCOL_FEE() external view returns (uint16);
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
}

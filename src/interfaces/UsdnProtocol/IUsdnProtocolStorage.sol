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
     * @notice Divisor for the percentage values (safety margin)
     * @dev Example: 200 -> 2%
     */
    function PERCENTAGE_DIVISOR() external view returns (uint256);

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

    /// @notice The pending fees that are accumulated in the protocol
    function pendingProtocolFee() external view returns (uint256);

    /**
     * @notice Set the fee percentage.
     * @param feeBips The fee percentage (in bips) to be charged.
     * @dev Fees are charged when transfers occur between the vault and the long
     * @dev example: 0.5% -> 50 bips
     */
    function setFeeBips(uint16 feeBips) external;

    /**
     * @notice Set the fee collector address.
     * @param feeCollector The address of the fee collector.
     * @dev The fee collector is the address that receives the fees charged by the protocol
     * @dev The fee collector must be different from zero address
     */
    function setFeeCollector(address feeCollector) external;
}

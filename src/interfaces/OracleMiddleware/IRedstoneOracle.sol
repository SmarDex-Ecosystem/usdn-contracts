// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

/**
 * @title Redstone Oracle interface
 * @notice Redstone Oracle is used to validate asset prices coming from the Redstone oracle
 * It is used by the USDN protocol to get the price of the underlying asset
 */
interface IRedstoneOracle {
    /// @notice Interval between two Redstone price updates
    function REDSTONE_HEARTBEAT() external pure returns (uint48);

    /// @notice Number of decimals for prices contained in Redstone price updates
    function REDSTONE_DECIMALS() external pure returns (uint8);

    /// @notice The ID of the Redstone price feed
    function getRedstoneFeedId() external view returns (bytes32);

    /// @notice The maximum age of a recent price to be considered valid
    function getRedstoneRecentPriceDelay() external view returns (uint48);
}

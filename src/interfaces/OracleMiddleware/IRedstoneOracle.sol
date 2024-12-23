// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

interface IRedstoneOracle {
    /**
     * @notice Gets the interval between two Redstone price updates.
     * @return heartbeat_ The interval in seconds.
     */
    function REDSTONE_HEARTBEAT() external pure returns (uint48 heartbeat_);

    /**
     * @notice Gets the number of decimals for prices contained in Redstone price updates.
     * @return decimals_ The number of decimals.
     */
    function REDSTONE_DECIMALS() external pure returns (uint8 decimals_);

    /**
     * @notice Gets the ID of the Redstone price feed.
     * @return feedId_ The feed ID.
     */
    function getRedstoneFeedId() external view returns (bytes32 feedId_);

    /**
     * @notice Gets the maximum age of a price to be considered recent.
     * @return delay_ The age in seconds.
     */
    function getRedstoneRecentPriceDelay() external view returns (uint48 delay_);

    /**
     * @dev Used by the Redstone contract internally, we override it to allow all timestamps.
     * @param timestampMs The timestamp of the price update in milliseconds.
     */
    function validateTimestamp(uint256 timestampMs) external pure;
}

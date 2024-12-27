// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import { AggregatorV3Interface } from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

interface IChainlinkOracle {
    /**
     * @notice The sentinel value returned instead of the price if the data from the oracle is too old.
     * @return sentinelValue_ The sentinel value for "price too old".
     */
    function PRICE_TOO_OLD() external pure returns (int256 sentinelValue_);

    /**
     * @notice Gets the number of decimals of the asset from Chainlink.
     * @return decimals_ The number of decimals of the asset.
     */
    function getChainlinkDecimals() external view returns (uint256 decimals_);

    /**
     * @notice Gets the Chainlink price feed aggregator contract address.
     * @return priceFeed_ The address of the Chainlink price feed contract.
     */
    function getPriceFeed() external view returns (AggregatorV3Interface priceFeed_);

    /**
     * @notice Gets the duration after which the Chainlink data is considered stale or invalid.
     * @return limit_ The price validity duration.
     */
    function getChainlinkTimeElapsedLimit() external view returns (uint256 limit_);
}

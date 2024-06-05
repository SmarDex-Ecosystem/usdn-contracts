// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import { AggregatorV3Interface } from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

interface IChainlinkOracle {
    /**
     * @notice Price that indicates that the data returned by the oracle is too old
     * @return The sentinel value for "price too old"
     */
    function PRICE_TOO_OLD() external pure returns (int256);

    /**
     * @notice Get the number of decimals of the asset from Chainlink
     * @return decimals_ The number of decimals of the asset
     */
    function getChainlinkDecimals() external view returns (uint256 decimals_);

    /**
     * @notice Chainlink price feed aggregator contract address
     * @return The address of the chainlink price feed contract
     */
    function getPriceFeed() external view returns (AggregatorV3Interface);

    /**
     * @notice Duration after which the Chainlink data is considered stale or invalid
     * @return The price validity duration
     */
    function getChainlinkTimeElapsedLimit() external view returns (uint256);
}

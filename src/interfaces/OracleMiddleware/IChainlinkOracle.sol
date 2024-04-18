// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.0;

import { AggregatorV3Interface } from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

interface IChainlinkOracle {
    /**
     * @notice Get the number of decimals of the asset from Chainlink
     * @return decimals_ The number of decimals of the asset
     */
    function getChainlinkDecimals() external view returns (uint256 decimals_);

    /// @notice Returns the Chainlink price feed aggregator contract
    function getPriceFeed() external view returns (AggregatorV3Interface);

    /// @notice Returns the amount of time we consider the data from Chainlink valid.
    function getChainlinkTimeElapsedLimit() external view returns (uint256);
}

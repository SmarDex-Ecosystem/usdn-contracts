// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import { AggregatorV3Interface } from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import { AggregatorInterface } from "@chainlink/contracts/src/v0.8/interfaces/AggregatorInterface.sol";

/**
 * @title ChainlinkOracle contract
 * @notice This contract is used to get the price of an asset from Chainlink. It is used by the USDN protocol to get the
 * price of the USDN underlying asset.
 */
contract ChainlinkOracle {
    /// @notice Chainlink price feed aggregator contract
    AggregatorV3Interface immutable priceFeed;

    constructor(address _priceFeed) {
        priceFeed = AggregatorV3Interface(_priceFeed);
    }

    /**
     * @notice Get the price of the asset from Chainlink
     * @return price_ The price of the asset
     */
    function getPrice() public view returns (uint256 price_) {
        (, int256 _price,,,) = priceFeed.latestRoundData();
        price_ = uint256(_price);
    }

    /**
     * @notice Get the price of the asset from Chainlink, formatted to the specified number of decimals
     * @param _decimals The number of decimals to format the price to
     * @return formattedPrice_ The formatted price of the asset
     */
    function getFormattedPrice(uint256 _decimals) public view returns (uint256 formattedPrice_) {
        uint256 chainlinkDecimals = priceFeed.decimals();
        formattedPrice_ = getPrice() * (10 ** _decimals) / (10 ** chainlinkDecimals);
    }

    /**
     * @notice Get the number of decimals of the asset from Chainlink
     * @return decimals_ The number of decimals of the asset
     */
    function decimals() public view returns (uint256) {
        return priceFeed.decimals();
    }
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import { AggregatorV3Interface } from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import { AggregatorInterface } from "@chainlink/contracts/src/v0.8/interfaces/AggregatorInterface.sol";
import { PriceInfo } from "../../interfaces/IOracleMiddleware.sol";

/**
 * @title ChainlinkOracle contract
 * @notice This contract is used to get the price of an asset from Chainlink. It is used by the USDN protocol to get the
 * price of the USDN underlying asset.
 */
contract ChainlinkOracle {
    /// @notice Chainlink price feed aggregator contract
    AggregatorV3Interface public immutable _priceFeed;

    constructor(address priceFeed) {
        _priceFeed = AggregatorV3Interface(priceFeed);
    }

    /**
     * @notice Get the price of the asset from Chainlink
     * @return price_ The price of the asset
     */
    function getChainlinkPrice() public view returns (PriceInfo memory price_) {
        (, int256 price,, uint256 timestamp,) = _priceFeed.latestRoundData();
        price_ = PriceInfo(uint128(int128(price)), uint64(timestamp));
    }

    /**
     * @notice Get the price of the asset from Chainlink, formatted to the specified number of decimals
     * @param _decimals The number of decimals to format the price to
     * @return formattedPrice_ The formatted price of the asset
     */
    function getFormattedChainlinkPrice(uint256 _decimals) public view returns (PriceInfo memory formattedPrice_) {
        uint256 chainlinkDecimals = _priceFeed.decimals();
        formattedPrice_ = getChainlinkPrice();
        formattedPrice_.price = uint128(uint256(formattedPrice_.price) * (10 ** _decimals) / (10 ** chainlinkDecimals));
    }

    /**
     * @notice Get the number of decimals of the asset from Chainlink
     * @return decimals_ The number of decimals of the asset
     */
    function chainlinkOracleDecimals() public view returns (uint256) {
        return _priceFeed.decimals();
    }
}

// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import { AggregatorV3Interface } from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import { PriceInfo, ChainlinkPriceInfo } from "src/interfaces/OracleMiddleware/IOracleMiddlewareTypes.sol";
import { IOracleMiddlewareErrors } from "src/interfaces/OracleMiddleware/IOracleMiddlewareErrors.sol";

/**
 * @title ChainlinkOracle contract
 * @notice This contract is used to get the price of an asset from Chainlink. It is used by the USDN protocol to get the
 * price of the USDN underlying asset.
 */
contract ChainlinkOracle is IOracleMiddlewareErrors {
    /// @notice Chainlink price feed aggregator contract
    AggregatorV3Interface internal immutable _priceFeed;
    /// @notice Tolerated elapsed time until we consider the data too old
    uint256 internal _timeElapsedLimit;

    constructor(address chainlinkPriceFeed, uint256 timeElapsedLimit) {
        _priceFeed = AggregatorV3Interface(chainlinkPriceFeed);
        _timeElapsedLimit = timeElapsedLimit;
    }

    /**
     * @notice Get the price of the asset from Chainlink
     * @return price_ The price of the asset
     */
    function getChainlinkPrice() internal view returns (ChainlinkPriceInfo memory price_) {
        // slither-disable-next-line unused-return
        (, int256 price,, uint256 timestamp,) = _priceFeed.latestRoundData();

        if (timestamp < block.timestamp - _timeElapsedLimit) {
            price = -1;
        }

        price_ = ChainlinkPriceInfo({ price: price, neutralPrice: price, timestamp: timestamp });
    }

    /**
     * @notice Get the price of the asset from Chainlink, formatted to the specified number of decimals
     * @param decimals The number of decimals to format the price to
     * @return formattedPrice_ The formatted price of the asset
     */
    function getFormattedChainlinkPrice(uint256 decimals)
        internal
        view
        returns (ChainlinkPriceInfo memory formattedPrice_)
    {
        uint256 oracleDecimal = _priceFeed.decimals();
        formattedPrice_ = getChainlinkPrice();
        formattedPrice_.price = formattedPrice_.price * int256(10 ** decimals) / int256(10 ** oracleDecimal);
        formattedPrice_.neutralPrice = formattedPrice_.price;
    }

    /**
     * @notice Get the number of decimals of the asset from Chainlink
     * @return decimals_ The number of decimals of the asset
     */
    function chainlinkDecimals() public view returns (uint256) {
        return _priceFeed.decimals();
    }

    /// @notice Returns the Chainlink price feed aggregator contract
    function priceFeed() public view returns (AggregatorV3Interface) {
        return _priceFeed;
    }
}

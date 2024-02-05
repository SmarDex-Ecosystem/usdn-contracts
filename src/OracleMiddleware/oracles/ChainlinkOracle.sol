// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import { AggregatorV3Interface } from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import { PriceInfo } from "src/interfaces/OracleMiddleware/IOracleMiddlewareTypes.sol";
import { IOracleMiddlewareErrors } from "src/interfaces/OracleMiddleware/IOracleMiddlewareErrors.sol";

/**
 * @title ChainlinkOracle contract
 * @notice This contract is used to get the price of an asset from Chainlink. It is used by the USDN protocol to get the
 * price of the USDN underlying asset.
 */
contract ChainlinkOracle is IOracleMiddlewareErrors {
    /// @notice Chainlink price feed aggregator contract
    AggregatorV3Interface internal immutable _priceFeed;

    constructor(address chainlinkPriceFeed) {
        _priceFeed = AggregatorV3Interface(chainlinkPriceFeed);
    }

    /**
     * @notice Get the price of the asset from Chainlink
     * @return price_ The price of the asset
     */
    function getChainlinkPrice() internal view returns (PriceInfo memory price_) {
        // slither-disable-next-line unused-return
        (, int256 price,, uint256 timestamp,) = _priceFeed.latestRoundData();

        if (timestamp < block.timestamp - 1 hours) {
            revert OracleMiddlewarePriceTooOld(price, timestamp);
        }

        if (price < 0) {
            revert OracleMiddlewareWrongPrice(price);
        }

        // slither-disable-next-line unused-return
        price_ = PriceInfo({ price: uint256(price), neutralPrice: uint256(price), timestamp: timestamp });
    }

    /**
     * @notice Get the price of the asset from Chainlink, formatted to the specified number of decimals
     * @param decimals The number of decimals to format the price to
     * @return formattedPrice_ The formatted price of the asset
     */
    function getFormattedChainlinkPrice(uint256 decimals) internal view returns (PriceInfo memory formattedPrice_) {
        uint256 oracleDecimal = _priceFeed.decimals();
        formattedPrice_ = getChainlinkPrice();
        formattedPrice_.price = uint256(formattedPrice_.price) * (10 ** decimals) / (10 ** oracleDecimal);
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

// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

/**
 * @notice The price and timestamp returned by the oracle middleware.
 * @param price The validated asset price, potentially adjusted by the middleware.
 * @param neutralPrice The neutral/average price of the asset.
 * @param timestamp The timestamp of the price data.
 */
struct PriceInfo {
    uint256 price;
    uint256 neutralPrice;
    uint256 timestamp;
}

/**
 * @notice The price and timestamp returned by the Chainlink oracle.
 * @param price The asset price formatted by the middleware.
 * @param timestamp When the price was published on chain.
 */
struct ChainlinkPriceInfo {
    int256 price;
    uint256 timestamp;
}

/**
 * @notice Representation of a Pyth price with a uint256 price.
 * @param price The price of the asset.
 * @param conf The confidence interval around the price (in dollars, absolute value).
 * @param publishTime Unix timestamp describing when the price was published.
 */
struct FormattedPythPrice {
    uint256 price;
    uint256 conf;
    uint256 publishTime;
}

/**
 * @notice The price and timestamp returned by the Redstone oracle.
 * @param price The asset price formatted by the middleware.
 * @param timestamp The timestamp of the price data.
 */
struct RedstonePriceInfo {
    uint256 price;
    uint256 timestamp;
}

/**
 * @notice Represents the options for the low latency price adjustment.
 * @dev Used to determine how the price is adjusted based on protocol action.
 * @param Up Price adjusted to the upper bound.
 * @param Down Price adjusted to the lower bound.
 * @param None Neutral price without any adjustments.
 */
enum PriceAdjustment {
    Up,
    Down,
    None
}

/**
 * @notice Representation of data streams asset price with a uint256 price.
 * @param timestamp The timestamp of the asset price.
 * @param price The price of the asset with 18 decimals.
 * @param bid The simulated price impact of a buy order.
 * @param ask The simulated price impact of a sell order.
 */
struct FormattedDataStreamsPrice {
    uint256 timestamp;
    uint256 price;
    uint256 ask;
    uint256 bid;
}

// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.0;

/**
 * @notice The price and timestamp returned by the oracle middleware.
 * @dev The timestamp is the timestamp of the price data, not the timestamp of the request.
 * There is no need for optimization here, the struct is only used in memory and not in storage.
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
 * @notice The price and timestamp returned by the chainlink oracle.
 * @dev The timestamp is the timestamp of the price data, not the timestamp of the request.
 * There is no need for optimization here, the struct is only used in memory and not in storage.
 * @param price The asset price formatted by the middleware.
 * @param timestamp The timestamp of the price data.
 */
struct ChainlinkPriceInfo {
    int256 price;
    uint256 timestamp;
}

/**
 * @notice Struct representing a Pyth price with a int256 price.
 * @param price The price of the asset
 * @param conf The confidence interval around the price (in dollars, absolute value)
 * @param expo The number of decimals of the price
 * @param publishTime Unix timestamp describing when the price was published
 */
struct FormattedPythPrice {
    int256 price;
    uint256 conf;
    int128 expo;
    uint128 publishTime;
}

/**
 * @notice Enum representing the confidence interval of a Pyth price.
 * Used by the middleware determine which price to use in a confidence interval.
 */
enum ConfidenceInterval {
    Up,
    Down,
    None
}

/**
 * @notice All possible price oracles for the protocol.
 * @param None No particular oracle.
 * @param Pyth Pyth Network.
 * @param ChainlinkDataStream Chainlink Data Stream.
 * @param ChainlinkOnChain Chainlink On-Chain.
 */
enum Oracle {
    None,
    Pyth,
    ChainlinkDataStream,
    ChainlinkOnChain
}

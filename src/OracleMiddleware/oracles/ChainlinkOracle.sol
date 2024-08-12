// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import { AggregatorV3Interface } from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

import { IChainlinkOracle } from "../../interfaces/OracleMiddleware/IChainlinkOracle.sol";
import { IOracleMiddlewareErrors } from "../../interfaces/OracleMiddleware/IOracleMiddlewareErrors.sol";
import { ChainlinkPriceInfo } from "../../interfaces/OracleMiddleware/IOracleMiddlewareTypes.sol";

/**
 * @title ChainlinkOracle contract
 * @notice This contract is used to get the price of an asset from Chainlink. It is used by the USDN protocol to get the
 * price of the USDN underlying asset, and by the LiquidationRewardsManager to get the price of the gas
 */
abstract contract ChainlinkOracle is IChainlinkOracle, IOracleMiddlewareErrors {
    /// @inheritdoc IChainlinkOracle
    int256 public constant PRICE_TOO_OLD = type(int256).min;

    /// @notice Chainlink price feed aggregator contract
    AggregatorV3Interface internal immutable _priceFeed;

    /// @notice Tolerated elapsed time until we consider the data too old
    // slither-disable-next-line immutable-states
    uint256 internal _timeElapsedLimit;

    /**
     * @param chainlinkPriceFeed Address of the price feed
     * @param timeElapsedLimit Tolerated elapsed time before that data is considered invalid
     */
    constructor(address chainlinkPriceFeed, uint256 timeElapsedLimit) {
        _priceFeed = AggregatorV3Interface(chainlinkPriceFeed);
        _timeElapsedLimit = timeElapsedLimit;
    }

    /// @inheritdoc IChainlinkOracle
    function getChainlinkDecimals() public view returns (uint256) {
        return _priceFeed.decimals();
    }

    /// @inheritdoc IChainlinkOracle
    function getPriceFeed() public view returns (AggregatorV3Interface) {
        return _priceFeed;
    }

    /// @inheritdoc IChainlinkOracle
    function getChainlinkTimeElapsedLimit() external view returns (uint256) {
        return _timeElapsedLimit;
    }

    /**
     * @notice Get the latest price of the asset from Chainlink
     * @dev If the price returned equals PRICE_TOO_OLD, it means the price is too old
     * @return price_ The price of the asset
     */
    function _getChainlinkLatestPrice() internal view virtual returns (ChainlinkPriceInfo memory price_) {
        (, int256 price,, uint256 timestamp,) = _priceFeed.latestRoundData();

        if (timestamp < block.timestamp - _timeElapsedLimit) {
            price = PRICE_TOO_OLD;
        }

        price_ = ChainlinkPriceInfo({ price: price, timestamp: timestamp });
    }

    /**
     * @notice Get the latest price of the asset from Chainlink, formatted to the specified number of decimals
     * @param middlewareDecimals The number of decimals to format the price to
     * @return formattedPrice_ The formatted price of the asset
     */
    function _getFormattedChainlinkLatestPrice(uint256 middlewareDecimals)
        internal
        view
        returns (ChainlinkPriceInfo memory formattedPrice_)
    {
        uint8 oracleDecimals = _priceFeed.decimals();
        formattedPrice_ = _getChainlinkLatestPrice();
        if (formattedPrice_.price == PRICE_TOO_OLD) {
            return formattedPrice_;
        }

        formattedPrice_.price = formattedPrice_.price * int256(10 ** middlewareDecimals) / int256(10 ** oracleDecimals);
    }

    /**
     * @notice Get a specified roundId price of the asset from Chainlink, formatted to the specified number of decimals
     * @param middlewareDecimals The number of decimals to format the price to
     * @param roundId The targeted roundId
     * @return formattedPrice_ The formatted price of the asset
     */
    function _getFormattedChainlinkPrice(uint256 middlewareDecimals, uint80 roundId)
        internal
        view
        returns (ChainlinkPriceInfo memory formattedPrice_)
    {
        uint8 oracleDecimals = _priceFeed.decimals();
        formattedPrice_ = _getChainlinkPrice(roundId);
        if (formattedPrice_.price <= 0) {
            return formattedPrice_;
        }
        formattedPrice_.price = formattedPrice_.price * int256(10 ** middlewareDecimals) / int256(10 ** oracleDecimals);
    }

    /**
     * @notice Get the targeted roundId price of the asset from Chainlink
     * @param roundId The chainlink roundId price
     * @return price_ The price of the asset
     */
    function _getChainlinkPrice(uint80 roundId) internal view virtual returns (ChainlinkPriceInfo memory price_) {
        (, price_.price,, price_.timestamp,) = _priceFeed.getRoundData(roundId);
    }
}

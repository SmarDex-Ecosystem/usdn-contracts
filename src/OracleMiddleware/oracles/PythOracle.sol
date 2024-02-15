// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import { IPyth } from "@pythnetwork/pyth-sdk-solidity/IPyth.sol";
import { PythStructs } from "@pythnetwork/pyth-sdk-solidity/PythStructs.sol";

import { FormattedPythPrice } from "src/interfaces/OracleMiddleware/IOracleMiddlewareTypes.sol";
import { IOracleMiddlewareErrors } from "src/interfaces/OracleMiddleware/IOracleMiddlewareErrors.sol";

/**
 * @title PythOracle contract
 * @notice This contract is used to get the price of an asset from pyth. It is used by the USDN protocol to get the
 * price of the USDN underlying asset.
 */
abstract contract PythOracle is IOracleMiddlewareErrors {
    uint256 private constant DECIMALS = 8;

    bytes32 internal immutable _priceID;
    IPyth internal immutable _pyth;

    /// @notice The maximum age of a recent price to be considered valid
    uint64 internal _recentPriceDelay = 45 seconds;

    constructor(address pythAddress, bytes32 pythPriceID) {
        _pyth = IPyth(pythAddress);
        _priceID = pythPriceID;
    }

    /**
     * @notice Get the price of the asset from pyth
     * @param priceUpdateData The data required to update the price feed
     * @param targetTimestamp The target timestamp to validate the price. If zero, then we accept all recent prices.
     * @return price_ The price of the asset
     */
    function getPythPrice(bytes calldata priceUpdateData, uint64 targetTimestamp)
        internal
        returns (PythStructs.Price memory)
    {
        // Parse the price feed update and get the price feed
        bytes32[] memory priceIds = new bytes32[](1);
        priceIds[0] = _priceID;

        bytes[] memory pricesUpdateData = new bytes[](1);
        pricesUpdateData[0] = priceUpdateData;

        PythStructs.PriceFeed[] memory priceFeeds;
        if (targetTimestamp == 0) {
            // we want to validate that the price is recent
            priceFeeds = _pyth.parsePriceFeedUpdatesUnique{ value: msg.value }(
                pricesUpdateData, priceIds, uint64(block.timestamp) - _recentPriceDelay, uint64(block.timestamp)
            );
        } else {
            priceFeeds = _pyth.parsePriceFeedUpdatesUnique{ value: msg.value }(
                pricesUpdateData, priceIds, targetTimestamp, type(uint64).max
            );
        }

        if (priceFeeds[0].price.price < 0) {
            revert OracleMiddlewareWrongPrice(priceFeeds[0].price.price);
        }

        return priceFeeds[0].price;
    }

    /**
     * @notice Get the price of the asset from pyth, formatted to the specified number of decimals
     * @param priceUpdateData The data required to update the price feed
     * @param targetTimestamp The target timestamp to validate the price. If zero, then we accept all recent prices.
     * @param _decimals The number of decimals to format the price to
     */
    function getFormattedPythPrice(bytes calldata priceUpdateData, uint64 targetTimestamp, uint256 _decimals)
        internal
        returns (FormattedPythPrice memory pythPrice_)
    {
        PythStructs.Price memory pythPrice = getPythPrice(priceUpdateData, targetTimestamp);

        pythPrice_ = FormattedPythPrice({
            price: int256(uint256(uint64(pythPrice.price)) * 10 ** _decimals / 10 ** DECIMALS),
            conf: uint256(uint256(uint64(pythPrice.conf)) * 10 ** _decimals / 10 ** DECIMALS),
            expo: pythPrice.expo,
            publishTime: uint128(pythPrice.publishTime)
        });
    }

    /**
     * @notice Get the price of the fee to update the price feed
     * @param priceUpdateData The data required to update the price feed
     * @return updateFee_ The price of the fee to update the price feed
     */
    function getPythUpdateFee(bytes calldata priceUpdateData) internal view returns (uint256) {
        bytes[] memory pricesUpdateData = new bytes[](1);
        pricesUpdateData[0] = priceUpdateData;

        return _pyth.getUpdateFee(pricesUpdateData);
    }

    /**
     * @notice Get the number of decimals of the asset from Pyth network
     * @return decimals_ The number of decimals of the asset
     */
    function pythDecimals() public pure returns (uint256) {
        return DECIMALS;
    }

    /**
     * @notice Get the Pyth contract address
     * @return pyth_ The Pyth contract address
     */
    function pyth() public view returns (IPyth) {
        return _pyth;
    }

    /**
     * @notice Get the Pyth price ID
     * @return priceID_ The Pyth price ID
     */
    function priceID() public view returns (bytes32) {
        return _priceID;
    }

    /**
     * @notice Get the recent price delay
     * @return recentPriceDelay_ The maximum age of a recent price to be considered valid
     */
    function getRecentPriceDelay() external view returns (uint64) {
        return _recentPriceDelay;
    }
}

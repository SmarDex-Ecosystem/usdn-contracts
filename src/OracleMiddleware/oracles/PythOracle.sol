// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import { IPyth } from "@pythnetwork/pyth-sdk-solidity/IPyth.sol";
import { PythStructs } from "@pythnetwork/pyth-sdk-solidity/PythStructs.sol";

import { IPythOracle } from "src/interfaces/OracleMiddleware/IPythOracle.sol";
import { FormattedPythPrice } from "src/interfaces/OracleMiddleware/IOracleMiddlewareTypes.sol";
import { IOracleMiddlewareErrors } from "src/interfaces/OracleMiddleware/IOracleMiddlewareErrors.sol";

/**
 * @title PythOracle contract
 * @notice This contract is used to get the price of an asset from pyth. It is used by the USDN protocol to get the
 * price of the USDN underlying asset
 */
abstract contract PythOracle is IPythOracle, IOracleMiddlewareErrors {
    /// @notice The ID of the Pyth price feed
    bytes32 internal immutable _pythFeedId;

    /// @notice The address of the Pyth contract
    IPyth internal immutable _pyth;

    /// @notice The maximum age of a recent price to be considered valid
    uint64 internal _pythRecentPriceDelay = 45 seconds;

    /**
     * @param pythAddress The address of the Pyth contract
     * @param pythFeedId The ID of the Pyth price feed
     */
    constructor(address pythAddress, bytes32 pythFeedId) {
        _pyth = IPyth(pythAddress);
        _pythFeedId = pythFeedId;
    }

    /// @inheritdoc IPythOracle
    function getPyth() external view returns (IPyth) {
        return _pyth;
    }

    /// @inheritdoc IPythOracle
    function getPythFeedId() external view returns (bytes32) {
        return _pythFeedId;
    }

    /// @inheritdoc IPythOracle
    function getPythRecentPriceDelay() external view returns (uint64) {
        return _pythRecentPriceDelay;
    }

    /**
     * @notice Get the price of the asset from pyth
     * @param priceUpdateData The data required to update the price feed
     * @param targetTimestamp The target timestamp to validate the price. If zero, then we accept all recent prices
     * @return price_ The price of the asset
     */
    function _getPythPrice(bytes calldata priceUpdateData, uint128 targetTimestamp)
        internal
        returns (PythStructs.Price memory)
    {
        // parse the price feed update and get the price feed
        bytes32[] memory feedIds = new bytes32[](1);
        feedIds[0] = _pythFeedId;

        bytes[] memory pricesUpdateData = new bytes[](1);
        pricesUpdateData[0] = priceUpdateData;

        uint256 pythFee = _pyth.getUpdateFee(pricesUpdateData);
        // sanity check on the fee requested by Pyth
        if (pythFee > 0.01 ether) {
            revert OracleMiddlewarePythFeeSafeguard(pythFee);
        }
        if (msg.value != pythFee) {
            revert OracleMiddlewareIncorrectFee();
        }

        PythStructs.PriceFeed[] memory priceFeeds;
        if (targetTimestamp == 0) {
            // we want to validate that the price is recent
            // we don't enforce that the price update is the first one in a given second
            priceFeeds = _pyth.parsePriceFeedUpdates{ value: pythFee }(
                pricesUpdateData, feedIds, uint64(block.timestamp) - _pythRecentPriceDelay, uint64(block.timestamp)
            );
        } else {
            // we want to validate that the price is exactly at `targetTimestamp` (first in the second) or the next
            // available price in the future, as identified by the prevPublishTime being strictly less than
            // targetTimestamp
            priceFeeds = _pyth.parsePriceFeedUpdatesUnique{ value: pythFee }(
                pricesUpdateData, feedIds, uint64(targetTimestamp), type(uint64).max
            );
        }

        if (priceFeeds[0].price.price <= 0) {
            revert OracleMiddlewareWrongPrice(priceFeeds[0].price.price);
        }

        return priceFeeds[0].price;
    }

    /**
     * @notice Get the price of the asset from pyth, formatted to the specified number of decimals
     * @param priceUpdateData The data required to update the price feed
     * @param targetTimestamp The target timestamp to validate the price. If zero, then we accept all recent prices
     * @param middlewareDecimals The number of decimals to format the price to
     * @return price_ The Pyth price formatted with `middlewareDecimals`
     */
    function _getFormattedPythPrice(bytes calldata priceUpdateData, uint128 targetTimestamp, uint256 middlewareDecimals)
        internal
        returns (FormattedPythPrice memory price_)
    {
        // this call checks that the price is strictly positive
        PythStructs.Price memory pythPrice = _getPythPrice(priceUpdateData, targetTimestamp);

        if (pythPrice.expo > 0) {
            revert OracleMiddlewarePythPositiveExponent(pythPrice.expo);
        }

        price_ = _formatPythPrice(pythPrice, middlewareDecimals);
    }

    /**
     * @notice Format a Pyth price object to normalize to the specified number of decimals
     * @param pythPrice A Pyth price object
     * @param middlewareDecimals The number of decimals to format the price to
     * @return price_ The Pyth price formatted with `middlewareDecimals`
     */
    function _formatPythPrice(PythStructs.Price memory pythPrice, uint256 middlewareDecimals)
        internal
        pure
        returns (FormattedPythPrice memory price_)
    {
        uint256 pythDecimals = uint32(-pythPrice.expo);

        price_ = FormattedPythPrice({
            price: uint256(uint64(pythPrice.price)) * 10 ** middlewareDecimals / 10 ** pythDecimals,
            conf: uint256(pythPrice.conf) * 10 ** middlewareDecimals / 10 ** pythDecimals,
            publishTime: pythPrice.publishTime
        });
    }

    /**
     * @notice Get the price of the fee to update the price feed
     * @param priceUpdateData The data required to update the price feed
     * @return updateFee_ The price of the fee to update the price feed
     */
    function _getPythUpdateFee(bytes calldata priceUpdateData) internal view returns (uint256) {
        bytes[] memory pricesUpdateData = new bytes[](1);
        pricesUpdateData[0] = priceUpdateData;

        return _pyth.getUpdateFee(pricesUpdateData);
    }

    /**
     * @notice Get the latest seen (cached) price from the pyth contract
     * @param middlewareDecimals The number of decimals for the returned price
     * @return price_ The formatted cached Pyth price, or all-zero values if there was no valid pyth price on-chain
     */
    function _getLatestStoredPythPrice(uint256 middlewareDecimals)
        internal
        view
        returns (FormattedPythPrice memory price_)
    {
        // we use getPriceUnsafe to get the latest price without reverting, no matter how old
        PythStructs.Price memory pythPrice = _pyth.getPriceUnsafe(_pythFeedId);
        // negative or zero prices are considered invalid, we return zero
        if (pythPrice.price <= 0) {
            return price_;
        }
        price_ = _formatPythPrice(pythPrice, middlewareDecimals);
    }
}

// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import { IPyth } from "@pythnetwork/pyth-sdk-solidity/IPyth.sol";
import { PythStructs } from "@pythnetwork/pyth-sdk-solidity/PythStructs.sol";

import { IOracleMiddlewareErrors } from "../../interfaces/OracleMiddleware/IOracleMiddlewareErrors.sol";
import { FormattedPythPrice } from "../../interfaces/OracleMiddleware/IOracleMiddlewareTypes.sol";
import { IPythOracle } from "../../interfaces/OracleMiddleware/IPythOracle.sol";

/**
 * @title Contract To Communicate With The Pyth Oracle
 * @notice This contract is used to get the price of the asset that corresponds to the stored feed ID.
 * @dev Is implemented by the {OracleMiddleware} contract.
 */
abstract contract PythOracle is IPythOracle, IOracleMiddlewareErrors {
    /// @notice The ID of the Pyth price feed.
    bytes32 internal immutable _pythFeedId;

    /// @notice The address of the Pyth contract.
    IPyth internal immutable _pyth;

    /// @notice The maximum age of a recent price to be considered valid.
    uint64 internal _pythRecentPriceDelay = 45 seconds;

    /**
     * @param pythAddress The address of the Pyth contract.
     * @param pythFeedId The ID of the Pyth price feed.
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
     * @notice Gets the price of the asset from the stored Pyth price feed.
     * @param priceUpdateData The data required to update the price feed.
     * @param targetTimestamp The timestamp of the price in the given `priceUpdateData`.
     * If zero, then we accept all recent prices.
     * @param targetLimit The most recent timestamp a price can have.
     * Can be zero if `targetTimestamp` is zero.
     * @return price_ The raw price of the asset returned by Pyth.
     */
    function _getPythPrice(bytes calldata priceUpdateData, uint128 targetTimestamp, uint128 targetLimit)
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
            // we add a sanity check that this price update cannot be too late (more than `_lowLatencyDelay` seconds
            // late) compared to the desired targetTimestamp
            priceFeeds = _pyth.parsePriceFeedUpdatesUnique{ value: pythFee }(
                pricesUpdateData, feedIds, uint64(targetTimestamp), uint64(targetLimit)
            );
        }

        if (priceFeeds[0].price.price <= 0) {
            revert OracleMiddlewareWrongPrice(priceFeeds[0].price.price);
        }

        return priceFeeds[0].price;
    }

    /**
     * @notice Gets the price of the asset from Pyth, formatted to the specified number of decimals.
     * @param priceUpdateData The data required to update the price feed.
     * @param targetTimestamp The timestamp of the price in the given `priceUpdateData`.
     * If zero, then we accept all recent prices.
     * @param middlewareDecimals The number of decimals to format the price to.
     * @param targetLimit The most recent timestamp a price can have.
     * Can be zero if `targetTimestamp` is zero.
     * @return price_ The Pyth price formatted with `middlewareDecimals`.
     */
    function _getFormattedPythPrice(
        bytes calldata priceUpdateData,
        uint128 targetTimestamp,
        uint256 middlewareDecimals,
        uint128 targetLimit
    ) internal returns (FormattedPythPrice memory price_) {
        // this call checks that the price is strictly positive
        PythStructs.Price memory pythPrice = _getPythPrice(priceUpdateData, targetTimestamp, targetLimit);

        if (pythPrice.expo > 0) {
            revert OracleMiddlewarePythPositiveExponent(pythPrice.expo);
        }

        price_ = _formatPythPrice(pythPrice, middlewareDecimals);
    }

    /**
     * @notice Formats a Pyth price object to normalize to the specified number of decimals.
     * @param pythPrice A Pyth price object.
     * @param middlewareDecimals The number of decimals to format the price to.
     * @return price_ The Pyth price formatted with `middlewareDecimals`.
     */
    function _formatPythPrice(PythStructs.Price memory pythPrice, uint256 middlewareDecimals)
        internal
        pure
        returns (FormattedPythPrice memory price_)
    {
        uint256 pythDecimals = uint32(-pythPrice.expo);

        price_ = FormattedPythPrice({
            price: uint256(int256(pythPrice.price)) * 10 ** middlewareDecimals / 10 ** pythDecimals,
            conf: uint256(pythPrice.conf) * 10 ** middlewareDecimals / 10 ** pythDecimals,
            publishTime: pythPrice.publishTime
        });
    }

    /**
     * @notice Gets the fee required to update the price feed.
     * @param priceUpdateData The data required to update the price feed.
     * @return updateFee_ The fee required to update the price feed.
     */
    function _getPythUpdateFee(bytes calldata priceUpdateData) internal view returns (uint256) {
        bytes[] memory pricesUpdateData = new bytes[](1);
        pricesUpdateData[0] = priceUpdateData;

        return _pyth.getUpdateFee(pricesUpdateData);
    }

    /**
     * @notice Gets the latest seen (cached) price from the Pyth contract.
     * @param middlewareDecimals The number of decimals for the returned price.
     * @return price_ The formatted cached Pyth price, or all-zero values if there was no valid Pyth price on-chain.
     */
    function _getLatestStoredPythPrice(uint256 middlewareDecimals)
        internal
        view
        returns (FormattedPythPrice memory price_)
    {
        // we use getPriceUnsafe to get the latest price without reverting, no matter how old
        PythStructs.Price memory pythPrice;
        // if the proxy implementation changes, this can revert
        try _pyth.getPriceUnsafe(_pythFeedId) returns (PythStructs.Price memory unsafePrice_) {
            pythPrice = unsafePrice_;
        } catch { }

        // negative or zero prices are considered invalid, we return zero
        if (pythPrice.price <= 0) {
            return price_;
        }

        if (pythPrice.expo > 0) {
            revert OracleMiddlewarePythPositiveExponent(pythPrice.expo);
        }

        price_ = _formatPythPrice(pythPrice, middlewareDecimals);
    }
}

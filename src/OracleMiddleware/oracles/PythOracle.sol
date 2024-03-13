// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import { IPyth } from "@pythnetwork/pyth-sdk-solidity/IPyth.sol";
import { PythStructs } from "@pythnetwork/pyth-sdk-solidity/PythStructs.sol";

import { IPythOracle } from "src/interfaces/OracleMiddleware/IPythOracle.sol";
import { FormattedPythPrice } from "src/interfaces/OracleMiddleware/IOracleMiddlewareTypes.sol";
import { IOracleMiddlewareErrors } from "src/interfaces/OracleMiddleware/IOracleMiddlewareErrors.sol";

/**
 * @title PythOracle contract
 * @notice This contract is used to get the price of an asset from pyth. It is used by the USDN protocol to get the
 * price of the USDN underlying asset.
 */
abstract contract PythOracle is IPythOracle, IOracleMiddlewareErrors {
    uint256 internal constant DECIMALS = 8;

    bytes32 internal immutable _priceID;
    IPyth internal immutable _pyth;

    /// @notice The maximum age of a recent price to be considered valid
    uint64 internal _recentPriceDelay = 45 seconds;

    constructor(address pythAddress, bytes32 pythPriceID) {
        _pyth = IPyth(pythAddress);
        _priceID = pythPriceID;
    }

    /// @inheritdoc IPythOracle
    function getPythDecimals() public pure returns (uint256) {
        return DECIMALS;
    }

    /// @inheritdoc IPythOracle
    function getPyth() public view returns (IPyth) {
        return _pyth;
    }

    /// @inheritdoc IPythOracle
    function getPriceID() external view returns (bytes32) {
        return _priceID;
    }

    /// @inheritdoc IPythOracle
    function getRecentPriceDelay() external view returns (uint64) {
        return _recentPriceDelay;
    }

    /**
     * @notice Get the price of the asset from pyth
     * @param priceUpdateData The data required to update the price feed
     * @param targetTimestamp The target timestamp to validate the price. If zero, then we accept all recent prices.
     * @return price_ The price of the asset
     */
    function _getPythPrice(bytes calldata priceUpdateData, uint128 targetTimestamp)
        internal
        returns (PythStructs.Price memory)
    {
        // Parse the price feed update and get the price feed
        bytes32[] memory priceIds = new bytes32[](1);
        priceIds[0] = _priceID;

        bytes[] memory pricesUpdateData = new bytes[](1);
        pricesUpdateData[0] = priceUpdateData;

        uint256 pythFee = _pyth.getUpdateFee(pricesUpdateData);
        if (msg.value < pythFee) {
            revert OracleMiddlewareInsufficientFee();
        }
        PythStructs.PriceFeed[] memory priceFeeds;
        if (targetTimestamp == 0) {
            // we want to validate that the price is recent
            // we don't enforce that the price update is the first one in a given second
            priceFeeds = _pyth.parsePriceFeedUpdates{ value: pythFee }(
                pricesUpdateData, priceIds, uint64(block.timestamp) - _recentPriceDelay, uint64(block.timestamp)
            );
        } else {
            // we want to validate that the price is exactly at targetTimestamp (first in the second) or the next
            // available price in the future, as identified by the prevPublishTime being strictly less than
            // targetTimestamp
            priceFeeds = _pyth.parsePriceFeedUpdatesUnique{ value: pythFee }(
                pricesUpdateData, priceIds, uint64(targetTimestamp), type(uint64).max
            );
        }

        if (priceFeeds[0].price.price <= 0) {
            revert OracleMiddlewareWrongPrice(priceFeeds[0].price.price);
        }

        // refund unused ether
        if (address(this).balance > 0) {
            // slither-disable-next-line arbitrary-send-eth
            (bool success,) = payable(msg.sender).call{ value: address(this).balance }("");
            if (!success) {
                revert OracleMiddlewareEtherRefundFailed();
            }
        }

        return priceFeeds[0].price;
    }

    /**
     * @notice Get the price of the asset from pyth, formatted to the specified number of decimals
     * @param priceUpdateData The data required to update the price feed
     * @param targetTimestamp The target timestamp to validate the price. If zero, then we accept all recent prices.
     * @param decimals The number of decimals to format the price to
     */
    function _getFormattedPythPrice(bytes calldata priceUpdateData, uint128 targetTimestamp, uint256 decimals)
        internal
        returns (FormattedPythPrice memory pythPrice_)
    {
        // this call checks that the price is strictly positive
        PythStructs.Price memory pythPrice = _getPythPrice(priceUpdateData, targetTimestamp);

        pythPrice_ = FormattedPythPrice({
            price: uint256(uint64(pythPrice.price)) * 10 ** decimals / 10 ** DECIMALS,
            conf: uint256(pythPrice.conf) * 10 ** decimals / 10 ** DECIMALS,
            expo: pythPrice.expo,
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
}

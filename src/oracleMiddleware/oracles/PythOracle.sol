// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import { IPyth } from "@pythnetwork/pyth-sdk-solidity/IPyth.sol";
import { PythStructs } from "@pythnetwork/pyth-sdk-solidity/PythStructs.sol";

import { ConfidenceInterval, FormattedPythPrice } from "src/interfaces/IOracleMiddleware.sol";

/**
 * @title PythOracle contract
 * @author @yashiru
 * @notice This contract is used to get the price of an asset from pyth. It is used by the USDN protocol to get the
 * price of the USDN underlying asset.
 */
contract PythOracle {
    uint256 private constant DECIMALS = 8;

    bytes32 public immutable _priceID;
    IPyth public immutable _pyth;

    constructor(address pyth, bytes32 priceID) {
        _pyth = IPyth(pyth);
        _priceID = priceID;
    }

    /**
     * @notice Get the price of the asset from pyth
     * @param priceUpdateData The data required to update the price feed
     * @return price_ The price of the asset
     */
    function getPythPrice(bytes calldata priceUpdateData, uint64 targetTimestamp)
        public
        payable
        returns (PythStructs.Price memory)
    {
        // Parse the price feed update and get the price feed
        bytes32[] memory priceIds = new bytes32[](1);
        priceIds[0] = _priceID;

        bytes[] memory priceUpdateDatas = new bytes[](1);
        priceUpdateDatas[0] = priceUpdateData;

        try _pyth.parsePriceFeedUpdatesUnique(priceUpdateDatas, priceIds, targetTimestamp, type(uint64).max) returns (
            PythStructs.PriceFeed[] memory priceFeeds
        ) {
            return priceFeeds[0].price;
        } catch {
            return PythStructs.Price({
                price: -1, // negative price to indicate error
                conf: 0,
                expo: 0,
                publishTime: 0
            });
        }
    }

    /**
     * @notice Get the price of the asset from pyth, formatted to the specified number of decimals
     * @param priceUpdateData The data required to update the price feed
     * @param _decimals The number of decimals to format the price to
     */
    function getFormattedPythPrice(bytes calldata priceUpdateData, uint64 targetTimestamp, uint256 _decimals)
        public
        payable
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
        bytes[] memory priceUpdateDatas = new bytes[](1);
        priceUpdateDatas[0] = priceUpdateData;

        return _pyth.getUpdateFee(priceUpdateDatas);
    }

    /**
     * @notice Get the number of decimals of the asset from Pyth network
     * @return decimals_ The number of decimals of the asset
     */
    function pythDecimals() public pure returns (uint256) {
        return DECIMALS;
    }
}

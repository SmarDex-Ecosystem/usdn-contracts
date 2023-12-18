// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import { IPyth } from "@pythnetwork/pyth-sdk-solidity/IPyth.sol";
import { PythStructs } from "@pythnetwork/pyth-sdk-solidity/PythStructs.sol";

import { ConfidenceInterval } from "src/interfaces/IOracleMiddleware.sol";

/**
 * @title PythOracle contract
 * @author @yashiru
 * @notice This contract is used to get the price of an asset from pyth. It is used by the USDN protocol to get the
 * price of the USDN underlying asset.
 */
contract PythOracle {
    uint256 private constant DECIMALS = 8;

    bytes32 private immutable priceID;
    IPyth private immutable pyth;

    constructor(address _pyth, bytes32 _priceID) {
        pyth = IPyth(_pyth);
        priceID = _priceID;
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
        priceIds[0] = priceID;

        bytes[] memory priceUpdateDatas = new bytes[](1);
        priceUpdateDatas[0] = priceUpdateData;

        try pyth.parsePriceFeedUpdatesUnique(priceUpdateDatas, priceIds, targetTimestamp, type(uint64).max) returns (
            PythStructs.PriceFeed[] memory priceFeeds
        ) {
            return priceFeeds[0].price;
        } catch {
            return PythStructs.Price(-1, 0, 0, 0);
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
        returns (PythStructs.Price memory pythPrice)
    {
        pythPrice = getPythPrice(priceUpdateData, targetTimestamp); // * (10 ** _decimals) / (10 ** DECIMALS);
        pythPrice.price = pythPrice.price * int64(uint64((10 ** _decimals) / (10 ** DECIMALS)));
    }

    /**
     * @notice Get the number of decimals of the asset from Pyth network
     * @return decimals_ The number of decimals of the asset
     */
    function pythDecimals() public pure returns (uint256) {
        return DECIMALS;
    }
}

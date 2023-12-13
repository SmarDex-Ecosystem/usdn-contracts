// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import { IPyth } from "@pythnetwork/pyth-sdk-solidity/IPyth.sol";
import { PythStructs } from "@pythnetwork/pyth-sdk-solidity/PythStructs.sol";

/**
 * @title PythOracle contract
 * @author @yashiru
 * @notice This contract is used to get the price of an asset from pyth. It is used by the USDN protocol to get the
 * price of the USDN underlying asset.
 */
contract PythOracle {
    uint256 private constant DECIMALS = 8;

    bytes32 private _priceID;
    IPyth private _pyth;

    constructor(address pythContract, bytes32 priceID) {
        _pyth = IPyth(pythContract);
        _priceID = priceID;
    }

    /**
     * @notice Get the price of the asset from pyth
     * @param priceUpdateData The data required to update the price feed
     * @return price_ The price of the asset
     */
    function getPythPrice(bytes[] calldata priceUpdateData) public payable returns (PythStructs.Price memory) {
        // Update the prices to the latest available values and pay the required fee for it. The `priceUpdateData` data
        // should be retrieved from our off-chain Price Service API using the `pyth-evm-js` package.
        // See section "How Pyth Works on EVM Chains" below for more information.
        uint256 fee = _pyth.getUpdateFee(priceUpdateData);
        _pyth.updatePriceFeeds{ value: fee }(priceUpdateData);

        // Read the current value of _priceID, aborting the transaction if the price has not been updated recently.
        // Every chain has a default recency threshold which can be retrieved by calling the getValidTimePeriod()
        // function on the contract.
        // Please see IPyth.sol for variants of this function that support configurable recency thresholds and other
        // useful features.
        return _pyth.getPrice(_priceID);
    }

    /**
     * @notice Get the price of the asset from pyth, formatted to the specified number of decimals
     * @param priceUpdateData The data required to update the price feed
     * @param _decimals The number of decimals to format the price to
     */
    function getFormattedPythPrice(bytes[] calldata priceUpdateData, uint256 _decimals)
        public
        payable
        returns (PythStructs.Price memory pythPrice)
    {
        pythPrice = getPythPrice(priceUpdateData); // * (10 ** _decimals) / (10 ** DECIMALS);
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

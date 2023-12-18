// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import { PythStructs } from "@pythnetwork/pyth-sdk-solidity/PythStructs.sol";

import { PythOracle } from "src/oracleMiddleware/oracles/PythOracle.sol";
import { ProtocolAction } from "src/interfaces/UsdnProtocol/IUsdnProtocol.sol";
import { ChainlinkOracle } from "src/oracleMiddleware/oracles/ChainlinkOracle.sol";
import {
    IOracleMiddleware,
    IOracleMiddlewareErrors,
    PriceInfo,
    ConfidenceInterval
} from "src/interfaces/IOracleMiddleware.sol";

/**
 * @title OracleMiddleware contract
 * @notice This contract is used to get the price of an asset from different price oracle.
 * It is used by the USDN protocol to get the price of the USDN underlying asset.
 * @dev This contract is a middleware between the USDN protocol and the price oracles.
 * @author Yashiru
 */
contract OracleMiddleware is IOracleMiddleware, IOracleMiddlewareErrors, PythOracle, ChainlinkOracle {
    uint256 public validationDelay = 24 seconds;

    uint8 constant DECIMALS = 8;

    constructor(address pythContract, bytes32 pythPriceID, address chainlinkPriceFeed)
        PythOracle(pythContract, pythPriceID)
        ChainlinkOracle(chainlinkPriceFeed)
    { }

    /* -------------------------------------------------------------------------- */
    /*                          Price retrieval features                          */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice Parses and validates price data.
     * @dev The data format is specific to the middleware and is simply forwarded from the user transaction's calldata.
     * @param targetTimestamp The timestamp for which the price is requested. The middleware may use this to validate
     * whether the price is fresh enough.
     * @param action Type of action for which the price is requested. The middleware may use this to alter the
     * validation of the price or the returned price.
     * @param data Price data, the format varies from middleware to middleware and can be different depending on the
     * action.
     * @return result_ The price and timestamp as `PriceInfo`.
     */
    function parseAndValidatePrice(uint128 targetTimestamp, ProtocolAction action, bytes calldata data)
        external
        payable
        returns (PriceInfo memory result_)
    {
        // TODO: Try optimising this (maybe a if (... || ... || ...) ...)
        // TODO: Validate each ConfidanceInterval
        if (action == ProtocolAction.None) {
            result_ = getPythOrChainlinkDatastreamPrice(data, uint64(targetTimestamp), ConfidenceInterval.none);
        } else if (action == ProtocolAction.ValidateDeposit) {
            result_ = getPythOrChainlinkDatastreamPrice(data, uint64(targetTimestamp), ConfidenceInterval.down);
        } else if (action == ProtocolAction.ValidateWithdrawal) {
            result_ = getPythOrChainlinkDatastreamPrice(data, uint64(targetTimestamp), ConfidenceInterval.up);
        } else if (action == ProtocolAction.ValidateOpenPosition) {
            result_ = getPythOrChainlinkDatastreamPrice(data, uint64(targetTimestamp), ConfidenceInterval.up);
        } else if (action == ProtocolAction.ValidateClosePosition) {
            result_ = getPythOrChainlinkDatastreamPrice(data, uint64(targetTimestamp), ConfidenceInterval.down);
        } else if (action == ProtocolAction.Liquidation) {
            result_ = getPythOrChainlinkDatastreamPrice(data, uint64(targetTimestamp), ConfidenceInterval.down);
        } else if (action == ProtocolAction.InitiateDeposit) {
            result_ = getChainlinkOnChainPrice();
        } else if (action == ProtocolAction.InitiateWithdrawal) {
            result_ = getChainlinkOnChainPrice();
        } else if (action == ProtocolAction.InitiateOpenPosition) {
            result_ = getChainlinkOnChainPrice();
        } else if (action == ProtocolAction.InitiateClosePosition) {
            result_ = getChainlinkOnChainPrice();
        } else {
            // TODO: check if solidity already does this check thanks to the enum
            revert OracleMiddlewareUnsupportedAction(action);
        }
    }

    /* -------------------------------------------------------------------------- */
    /*                      Factorised price retrival methods                     */
    /* -------------------------------------------------------------------------- */

    function getPythOrChainlinkDatastreamPrice(bytes calldata data, uint64 targetTimestamp, ConfidenceInterval conf)
        private
        returns (PriceInfo memory price_)
    {
        // Fetch the price from Pyth, return a price at -1 if it fails
        PythStructs.Price memory pythPrice = getFormattedPythPrice(data, targetTimestamp, DECIMALS);

        if (pythPrice.price != -1) {
            // Apply the confidence interval
            // TODO: optimize ternary
            price_.price = conf == ConfidenceInterval.down
                ? uint64(pythPrice.price) - pythPrice.conf
                : conf == ConfidenceInterval.up ? uint64(pythPrice.price) + pythPrice.conf : uint64(pythPrice.price);
            price_.timestamp = uint128(pythPrice.publishTime);
        } else {
            // TODO: Use Chainlink data stream when Pyth fails
        }
    }

    function getChainlinkOnChainPrice() private view returns (PriceInfo memory) {
        return getFormattedChainlinkPrice(DECIMALS);
    }

    /* -------------------------------------------------------------------------- */
    /*                              Generic features                              */
    /* -------------------------------------------------------------------------- */

    /// @notice Returns the number of decimals for the price (constant)
    function decimals() external pure returns (uint8) {
        return DECIMALS;
    }

    /// @notice Returns the ETH cost of one price validation for the given action
    function validationCost(ProtocolAction action) external returns (uint256) { }
}

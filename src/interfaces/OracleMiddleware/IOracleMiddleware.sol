// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.0;

import { ProtocolAction } from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import { PriceInfo } from "src/interfaces/OracleMiddleware/IOracleMiddlewareTypes.sol";
import { IOracleMiddlewareErrors } from "src/interfaces/OracleMiddleware/IOracleMiddlewareErrors.sol";
import { IOracleMiddlewareEvents } from "src/interfaces/OracleMiddleware/IOracleMiddlewareEvents.sol";

/**
 * @title Oracle Middleware interface
 * @notice The oracle middleware is a contract that is called by the USDN protocol to validate price data. Using a
 * middleware allows the protocol to later upgrade to a new oracle logic without having modify the vault contract.
 */
interface IOracleMiddleware is IOracleMiddlewareErrors, IOracleMiddlewareEvents {
    /* -------------------------------------------------------------------------- */
    /*                          Price retrieval features                          */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice Parses and validates price data.
     * @dev The data format is specific to the middleware and is simply forwarded from the user transaction's calldata.
     * @param targetTimestamp The target timestamp for validating the price data. For validation actions, this is the
     * timestamp of the initiation.
     * @param action Type of action for which the price is requested. The middleware may use this to alter the
     * validation of the price or the returned price.
     * @param data Price data, the format varies from middleware to middleware and can be different depending on the
     * action.
     * @return result_ The price and timestamp as `PriceInfo`.
     */
    function parseAndValidatePrice(uint128 targetTimestamp, ProtocolAction action, bytes calldata data)
        external
        payable
        returns (PriceInfo memory result_);

    /* -------------------------------------------------------------------------- */
    /*                              Generic features                              */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice Returns the delay (in seconds) between the moment an action is initiated and the timestamp of the
     * price data used to validate that action.
     */
    function getValidationDelay() external view returns (uint256);

    /// @notice Returns the amount of time we consider the data from Chainlink valid.
    function getChainlinkTimeElapsedLimit() external view returns (uint256);

    /// @notice Returns the number of decimals for the price (constant)
    function getDecimals() external view returns (uint8);

    /**
     * @notice Returns the ETH cost of one price validation for the given action
     * @param data Pyth price data to be validated for which to get fee prices
     * @param action Type of action for which the price is requested.
     * @return The ETH cost of one price validation
     */
    function validationCost(bytes calldata data, ProtocolAction action) external view returns (uint256);

    /* -------------------------------------------------------------------------- */
    /*                               Owner features                               */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice Set the "validation delay" (in seconds) between an action timestamp and the price
     * data timestamp used to validate that action.
     * @param newValidationDelay The new validation delay
     */
    function setValidationDelay(uint256 newValidationDelay) external;

    /**
     * @notice Set the elapsed time tolerated before we consider the price invalid for the chainlink oracle.
     * @param newTimeElapsedLimit The new time elapsed limit
     */
    function setChainlinkTimeElapsedLimit(uint256 newTimeElapsedLimit) external;

    /**
     * @notice Set the recent price delay
     * @param newDelay The maximum age of a recent price to be considered valid
     */
    function setRecentPriceDelay(uint64 newDelay) external;
}

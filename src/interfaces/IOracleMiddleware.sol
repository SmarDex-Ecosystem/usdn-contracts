// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import { ProtocolAction } from "src/interfaces/UsdnProtocol/IUsdnProtocol.sol";

/**
 * @title Oracle Middleware interface
 * @notice The oracle middleware is a contract that is called by the USDN protocol to validate price data. Using a
 * middleware allows the protocol to later upgrade to a new oracle logic without having modify the vault contract.
 */
interface IOracleMiddleware {
    /**
     * @notice Parses and validates price data.
     * @dev The data format is specific to the middleware and is simply forwarded from the user transaction's calldata.
     * @param targetTimestamp The target timestamp for validating the price data. For validation actions, this is the
     * timestamp of the initiation.
     * @param action Type of action for which the price is requested. The middleware may use this to alter the
     * validation of the price or the returned price.
     * @param data Price data, the format varies from middleware to middleware and can be different depending on the
     * action.
     * @return The price and timestamp as `PriceInfo`.
     */
    function parseAndValidatePrice(uint128 targetTimestamp, ProtocolAction action, bytes calldata data)
        external
        payable
        returns (PriceInfo memory);

    /**
     * @notice Returns the delay (in seconds) between the moment an action is initiated and the timestamp of the
     * price data used to validate that action.
     */
    function validationDelay() external returns (uint256);

    /// @notice Returns the number of decimals for the price (constant)
    function decimals() external pure returns (uint8);

    /**
     * @notice Returns the ETH cost of one price validation for the given action
     * @param data Pyth price data to be validated for which to get fee prices
     * @param action Type of action for which the price is requested.
     * @return The ETH cost of one price validation
     */
    function validationCost(bytes calldata data, ProtocolAction action) external returns (uint256);
}

/* -------------------------------------------------------------------------- */
/*                                   Errors                                   */
/* -------------------------------------------------------------------------- */

/// @notice The oracle middleware errors.
interface IOracleMiddlewareErrors {
    /// @notice The price request does not respect the minimum validation delay
    error OracleMiddlewarePriceRequestTooEarly();
    /// @notice The requested price is outside the valid price range
    error OracleMiddlewareWrongPriceTimestamp(uint64 min, uint64 max, uint64 result);
    /// @notice The requested action is not supported by the middleware
    error OracleMiddlewareUnsupportedAction(ProtocolAction action);
    /// @notice The Pyth price validation failed
    error PythValidationFailed();
}

/* -------------------------------------------------------------------------- */
/*                     Oracle middleware struct and enums                     */
/* -------------------------------------------------------------------------- */

/**
 * @notice The price and timestamp returned by the oracle middleware.
 * @dev The timestamp is the timestamp of the price data, not the timestamp of the request.
 * @param price The validated asset price.
 * @param timestamp The timestamp of the price data.
 */
struct PriceInfo {
    uint104 price; // max 20_282_409_603_651
    uint104 neutralPrice; // max 20_282_409_603_651
    uint48 timestamp;
}

/**
 * @notice Struct representing a Pyth price with a int160 price.
 * @param price The price of the asset
 * @param conf The confidence interval around the price
 * @param expo The price exponent
 * @param publishTime Unix timestamp describing when the price was published
 */
struct FormattedPythPrice {
    int256 price;
    uint256 conf;
    int128 expo;
    uint128 publishTime;
}

/**
 * @notice Enum representing the confidence interval of a Pyth price.
 * Used by the middleware determine which price to use in a confidence interval.
 */
enum ConfidenceInterval {
    UP,
    DOWN,
    NONE
}

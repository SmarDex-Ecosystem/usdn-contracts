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
     * @param targetTimestamp The timestamp for which the price is requested. The middleware may use this to validate
     * whether the price is fresh enough.
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

    /// @notice Returns the number of decimals for the price (constant)
    function decimals() external view returns (uint8);

    /// @notice Returns the ETH cost of one price validation for the given action
    function validationCost(ProtocolAction action) external returns (uint256);

    /**
     * @notice Returns the delay (in seconds) between the timestamp of initiating an action, and the timestamp of the
     * price data that is used to validate the action.
     */
    function validationDelay() external returns (uint256);
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
    uint128 price;
    uint128 timestamp;
}

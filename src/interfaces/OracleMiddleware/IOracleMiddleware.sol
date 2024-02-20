// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import { ProtocolAction } from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import { PriceInfo } from "src/interfaces/OracleMiddleware/IOracleMiddlewareTypes.sol";
import { IOracleMiddlewareErrors } from "src/interfaces/OracleMiddleware/IOracleMiddlewareErrors.sol";

/**
 * @title Oracle Middleware interface
 * @notice The oracle middleware is a contract that is called by the USDN protocol to validate price data. Using a
 * middleware allows the protocol to later upgrade to a new oracle logic without having modify the vault contract.
 */
interface IOracleMiddleware is IOracleMiddlewareErrors {
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

    /**
     * @notice Returns the delay (in seconds) between the moment an action is initiated and the timestamp of the
     * price data used to validate that action.
     */
    function validationDelay() external returns (uint256);

    /// @notice Returns the number of decimals for the price (constant)
    function decimals() external view returns (uint8);

    /**
     * @notice Returns the ETH cost of one price validation for the given action
     * @param data Pyth price data to be validated for which to get fee prices
     * @param action Type of action for which the price is requested.
     * @return The ETH cost of one price validation
     */
    function validationCost(bytes calldata data, ProtocolAction action) external returns (uint256);

    /**
     * @notice Update the "validation delay" (in seconds) between an action timestamp and the price
     *         data timestamp used to validate that action.
     * @param newDelay The new validation delay
     */
    function updateValidationDelay(uint256 newDelay) external;

    /// @notice get max confidence ratio
    function maxConfRatio() external pure returns (uint16);

    /// @notice get confidence ratio denominator
    function confRatioDenom() external pure returns (uint16);

    /**
     * @notice Return the confidence ratio. This ratio is used to apply a specific portion of the confidence interval
     * provided by an oracle, which is used to adjust the precision of predictions or estimations.
     */
    function confRatio() external view returns (uint16);

    /**
     * @notice Set confidence ratio (admin).
     * @param newConfRatio the new confidence ratio.
     * @dev New value should be lower than max confidence ratio.
     */
    function setConfRatio(uint16 newConfRatio) external;

    /**
     * @notice Emitted when the confidence ratio is updated.
     * @param newConfRatio new confidence ratio.
     */
    event ConfRatioSet(uint256 newConfRatio);
}

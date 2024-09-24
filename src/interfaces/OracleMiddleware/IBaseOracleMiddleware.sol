// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import { IUsdnProtocolTypes as Types } from "../UsdnProtocol/IUsdnProtocolTypes.sol";
import { PriceInfo } from "./IOracleMiddlewareTypes.sol";

/**
 * @title Base Oracle Middleware interface
 * @notice This interface exposes the only functions used or required by the UsdnProtocol
 * @dev Any future implementation of the oracle middleware must implement this interface without modification
 */
interface IBaseOracleMiddleware {
    /**
     * @notice Parse and validate some price data
     * @dev The data format is specific to the middleware and is simply forwarded from the user transaction's calldata
     * A fee amounting to exactly validationCost(data, action) must be sent or the transaction will revert
     * @param actionId A unique identifier for the current action. This identifier can be used to link a `Initiate`
     * call with the corresponding `Validate` call
     * @param targetTimestamp The target timestamp for validating the price data. For validation actions, this is the
     * timestamp of the initiation
     * @param action Type of action for which the price is requested. The middleware may use this to alter the
     * validation of the price or the returned price
     * @param data Price data, the format varies from middleware to middleware and can be different depending on the
     * action
     * @return result_ The price and timestamp as `PriceInfo`
     */
    function parseAndValidatePrice(
        bytes32 actionId,
        uint128 targetTimestamp,
        Types.ProtocolAction action,
        bytes calldata data
    ) external payable returns (PriceInfo memory result_);

    /**
     * @notice Get the required delay (in seconds) between the moment an action is initiated and the timestamp of the
     * price data used to validate that action
     * @return The validation delay
     */
    function getValidationDelay() external view returns (uint256);

    /**
     * @notice The maximum delay (in seconds) after initiation during which a low-latency price oracle can be used for
     * validation
     * @return The maximum delay for low-latency validation
     */
    function getLowLatencyDelay() external view returns (uint16);

    /**
     * @notice Returns the number of decimals for the price (constant)
     * @return The number of decimals
     */
    function getDecimals() external view returns (uint8);

    /**
     * @notice Returns the ETH cost of one price validation for the given action
     * @param data Pyth price data to be validated for which to get fee prices
     * @param action Type of action for which the price is requested
     * @return The ETH cost of one price validation
     */
    function validationCost(bytes calldata data, Types.ProtocolAction action) external view returns (uint256);
}

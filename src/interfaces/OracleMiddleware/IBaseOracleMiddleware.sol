// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import { IUsdnProtocolTypes as Types } from "../UsdnProtocol/IUsdnProtocolTypes.sol";
import { PriceInfo } from "./IOracleMiddlewareTypes.sol";

/**
 * @title Base Oracle Middleware interface
 * @notice This interface exposes the only functions used or required by the USDN Protocol.
 * @dev Any current or future implementation of the oracle middleware must be compatible with
 * this interface without any modification.
 */
interface IBaseOracleMiddleware {
    /**
     * @notice Parse and validate `data` and returns the corresponding price data.
     * @dev The data format is specific to the middleware and is simply forwarded from the user transaction's calldata.
     * A fee amounting to exactly {validationCost} (with the same `data` and `action`) must be sent or the transaction
     * will revert.
     * @param actionId A unique identifier for the current action. This identifier can be used to link an `Initiate`
     * call with the corresponding `Validate` call.
     * @param targetTimestamp The target timestamp for validating the price data. For validation actions, this is the
     * timestamp of the initiation.
     * @param action Type of action for which the price is requested. The middleware may use this to alter the
     * validation of the price or the returned price.
     * @param data The data to be used to communicate with oracles, the format varies from middleware to middleware and
     * can be different depending on the action.
     * @return result_ The price and timestamp as {IOracleMiddlewareTypes.PriceInfo}.
     */
    function parseAndValidatePrice(
        bytes32 actionId,
        uint128 targetTimestamp,
        Types.ProtocolAction action,
        bytes calldata data
    ) external payable returns (PriceInfo memory result_);

    /**
     * @notice Gets the required delay (in seconds) between the moment an action is initiated and the timestamp of the
     * price data used to validate that action.
     * @return delay_ The validation delay.
     */
    function getValidationDelay() external view returns (uint256 delay_);

    /**
     * @notice Gets The maximum amount of time (in seconds) after initiation during which a low-latency price oracle can
     * be used for validation.
     * @return delay_ The maximum delay for low-latency validation.
     */
    function getLowLatencyDelay() external view returns (uint16 delay_);

    /**
     * @notice Gets the number of decimals for the price.
     * @return decimals_ The number of decimals.
     */
    function getDecimals() external view returns (uint8 decimals_);

    /**
     * @notice Returns the cost of one price validation for the given action (in native token).
     * @param data Price data for which to get the fee.
     * @param action Type of the action for which the price is requested.
     * @return cost_ The cost of one price validation (in native token).
     */
    function validationCost(bytes calldata data, Types.ProtocolAction action) external view returns (uint256 cost_);
}

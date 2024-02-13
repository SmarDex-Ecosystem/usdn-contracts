// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import { ProtocolAction } from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";

/**
 * @title IOracleMiddlewareErrors
 * @notice Errors for the oracle middleware
 */
interface IOracleMiddlewareErrors {
    /// @notice The price request does not respect the minimum validation delay
    error OracleMiddlewarePriceRequestTooEarly();

    /// @notice The requested price is outside the valid price range
    error OracleMiddlewareOracleMiddlewareWrongPriceTimestamp(uint64 min, uint64 max, uint64 result);

    /// @notice The requested action is not supported by the middleware
    error OracleMiddlewareUnsupportedAction(ProtocolAction action);

    /// @notice The Pyth price validation failed
    error OracleMiddlewarePythValidationFailed();

    /// @notice The oracle price is invalid (negative)
    error OracleMiddlewareWrongPrice(int256 price);
}

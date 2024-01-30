// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import { ProtocolAction } from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";

/**
 * @title IOracleMiddlewareErrors
 * @notice Errors for the oracle middleware
 */
interface IOracleMiddlewareErrors {
    /// @dev The price request does not respect the minimum validation delay
    error OracleMiddlewarePriceRequestTooEarly();

    /// @dev The requested price is outside the valid price range
    error OracleMiddlewareWrongPriceTimestamp(uint64 min, uint64 max, uint64 result);

    /// @dev The requested action is not supported by the middleware
    error OracleMiddlewareUnsupportedAction(ProtocolAction action);

    /// @dev The Pyth price validation failed
    error PythValidationFailed();

    /// @dev The oracle price is invalid
    error WrongPrice(int256 price);

    /// @dev The oracle price is invalid
    error PriceTooOld(int256 price, uint256 timestamp);
}

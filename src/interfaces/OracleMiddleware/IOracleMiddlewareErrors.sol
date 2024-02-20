// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

/**
 * @title IOracleMiddlewareErrors
 * @notice Errors for the oracle middleware
 */
interface IOracleMiddlewareErrors {
    /// @notice The oracle price is invalid (negative)
    error OracleMiddlewareWrongPrice(int256 price);

    /// @notice The oracle price is invalid (too old)
    error OracleMiddlewarePriceTooOld(int256 price, uint256 timestamp);

    /// @notice the confidence ratio is too high
    error OracleMiddlewareConfRatioTooHigh();

    /// @notice Not enough ether was provided to cover the cost of price validation
    error OracleMiddlewareInsufficientFee();

    /// @notice The sender could not accept the ether refund
    error OracleMiddlewareEtherRefundFailed();

    /// @notice The recent price delay is invalid
    error OracleMiddlewareInvalidRecentPriceDelay(uint64 newDelay);
}

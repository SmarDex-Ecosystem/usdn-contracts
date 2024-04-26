// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.0;

/**
 * @title IOracleMiddlewareErrors
 * @notice Errors for the oracle middleware
 */
interface IOracleMiddlewareErrors {
    /**
     * @notice The oracle price is negative
     * @param price The price returned by the oracle
     */
    error OracleMiddlewareWrongPrice(int256 price);

    /**
     * @notice The oracle price is too old
     * @param timestamp The timestamp of the price given by the oracle
     */
    error OracleMiddlewarePriceTooOld(uint256 timestamp);

    /**
     * @notice The pyth price reported a positive exponent (negative decimals)
     * @param expo The price exponent
     */
    error OracleMiddlewarePythPositiveExponent(int32 expo);

    /// @notice the confidence ratio is too high
    error OracleMiddlewareConfRatioTooHigh();

    /// @notice An incorrect amount of ether was provided to cover the cost of price validation
    error OracleMiddlewareIncorrectFee();

    /**
     * @notice The withdrawal of the ether in the contract failed
     * @param to The address that was supposed to receive the ether
     */
    error OracleMiddlewareTransferFailed(address to);

    /// @notice The sender could not accept the ether refund
    error OracleMiddlewareEtherRefundFailed();

    /**
     * @notice The recent price delay is outside of the limits
     * @param newDelay The delay that was provided
     */
    error OracleMiddlewareInvalidRecentPriceDelay(uint64 newDelay);
}

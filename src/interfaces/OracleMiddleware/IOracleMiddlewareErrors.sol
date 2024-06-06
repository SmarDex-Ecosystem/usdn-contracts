// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

/**
 * @title IOracleMiddlewareErrors
 * @notice Errors for the oracle middleware
 */
interface IOracleMiddlewareErrors {
    /**
     * @notice Indicates that the oracle price is negative
     * @param price The price returned by the oracle
     */
    error OracleMiddlewareWrongPrice(int256 price);

    /**
     * @notice Indicates that the oracle price is too old
     * @param timestamp The timestamp of the price given by the oracle
     */
    error OracleMiddlewarePriceTooOld(uint256 timestamp);

    /**
     * @notice The oracle price is too recent
     * @param timestamp The timestamp of the price given by the oracle
     */
    error OracleMiddlewarePriceTooRecent(uint256 timestamp);

    /**
     * @notice Indicates that the pyth price reported a positive exponent (negative decimals)
     * @param expo The price exponent
     */
    error OracleMiddlewarePythPositiveExponent(int32 expo);

    /// @notice Indicates that the confidence ratio is too high
    error OracleMiddlewareConfRatioTooHigh();

    /// @notice Indicates that an incorrect amount of ether was provided to cover the cost of price validation
    error OracleMiddlewareIncorrectFee();

    /**
     * @notice The validation fee returned by the Pyth contract exceeded the safeguard value
     * @param fee The value of the fee returned by Pyth
     */
    error OracleMiddlewarePythFeeSafeguard(uint256 fee);

    /// @notice The redstone price is more than triple or less than a third of the latest chainlink price
    error OracleMiddlewareRedstoneSafeguard();

    /**
     * @notice Indicates that the withdrawal of the ether in the contract failed
     * @param to The address that was supposed to receive the ether
     */
    error OracleMiddlewareTransferFailed(address to);

    /// @notice Indicates that the address supposed to receive the ether is the zero address
    error OracleMiddlewareTransferToZeroAddress();

    /**
     * @notice Indicates that the recent price delay is outside of the limits
     * @param newDelay The delay that was provided
     */
    error OracleMiddlewareInvalidRecentPriceDelay(uint64 newDelay);

    /// @dev Indicates that the new penaltyBps value is invalid
    error OracleMiddlewareInvalidPenaltyBps();

    /// @notice Indicates that the chainlink roundId provided is invalid
    error OracleMiddlewareInvalidRoundId();

    /// @notice The new low latency delay is invalid
    error OracleMiddlewareInvalidLowLatencyDelay();
}

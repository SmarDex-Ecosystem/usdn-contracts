// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

/**
 * @title Errors For The Middleware And Oracle Related Contracts
 * @notice Defines all the custom errors thrown by the contracts related to the OracleMiddleware contract.
 */
interface IOracleMiddlewareErrors {
    /**
     * @notice The price returned by an oracle is negative.
     * @param price The price returned by the oracle.
     */
    error OracleMiddlewareWrongPrice(int256 price);

    /**
     * @notice The price returned by an oracle is too old.
     * @param timestamp The timestamp of the price given by the oracle.
     */
    error OracleMiddlewarePriceTooOld(uint256 timestamp);

    /**
     * @notice The price returned by an oracle is too recent.
     * @param timestamp The timestamp of the price given by the oracle.
     */
    error OracleMiddlewarePriceTooRecent(uint256 timestamp);

    /**
     * @notice The Pyth price reported a positive exponent (negative decimals).
     * @param expo The price exponent.
     */
    error OracleMiddlewarePythPositiveExponent(int32 expo);

    /// @notice Indicates that the confidence ratio is too high.
    error OracleMiddlewareConfRatioTooHigh();

    /// @notice Indicates that an incorrect amount of tokens was provided to cover the cost of price validation.
    error OracleMiddlewareIncorrectFee();

    /**
     * @notice The validation fee returned by the Pyth contract exceeded the safeguard value.
     * @param fee The required fee returned by Pyth.
     */
    error OracleMiddlewarePythFeeSafeguard(uint256 fee);

    /// @notice The Redstone price is to divergent from the Chainlink price.
    error OracleMiddlewareRedstoneSafeguard();

    /**
     * @notice The withdrawal of the Ether in the contract failed.
     * @param to The address of the intended recipient.
     */
    error OracleMiddlewareTransferFailed(address to);

    /// @notice The recipient of a transfer is the zero address.
    error OracleMiddlewareTransferToZeroAddress();

    /**
     * @notice The recent price delay is outside of the limits.
     * @param newDelay The delay that was provided.
     */
    error OracleMiddlewareInvalidRecentPriceDelay(uint64 newDelay);

    /// @dev The new penalty is invalid.
    error OracleMiddlewareInvalidPenaltyBps();

    /// @notice The provided Chainlink round ID is invalid.
    error OracleMiddlewareInvalidRoundId();

    /// @notice The new low latency delay is invalid.
    error OracleMiddlewareInvalidLowLatencyDelay();
}

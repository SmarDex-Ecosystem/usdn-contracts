// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

/**
 * @title Events For The Middleware And Oracle Related Contracts
 * @notice Defines all the custom events emitted by the contracts related to the OracleMiddleware contract.
 */
interface IOracleMiddlewareEvents {
    /**
     * @notice The time elapsed limit was updated.
     * @param newTimeElapsedLimit The new limit.
     */
    event TimeElapsedLimitUpdated(uint256 newTimeElapsedLimit);

    /**
     * @notice The validation delay was updated.
     * @param newValidationDelay The new validation delay.
     */
    event ValidationDelayUpdated(uint256 newValidationDelay);

    /**
     * @notice The recent price delay for Pyth was updated.
     * @param newDelay The new recent price delay.
     */
    event PythRecentPriceDelayUpdated(uint64 newDelay);

    /**
     * @notice The recent price delay for Chainlink data streams was updated.
     * @param newDelay The new recent price delay.
     */
    event DataStreamRecentPriceDelayUpdated(uint64 newDelay);

    /**
     * @notice The recent price delay for Redstone was updated.
     * @param newDelay The new recent price delay.
     */
    event RedstoneRecentPriceDelayUpdated(uint48 newDelay);

    /**
     * @notice The confidence ratio was updated.
     * @param newConfRatio The new confidence ratio.
     */
    event ConfRatioUpdated(uint256 newConfRatio);

    /**
     * @notice The penalty for Redstone prices was updated.
     * @param newPenaltyBps The new penalty.
     */
    event PenaltyBpsUpdated(uint16 newPenaltyBps);

    /**
     * @notice The low latency delay was updated.
     * @param newLowLatencyDelay The new low latency delay.
     */
    event LowLatencyDelayUpdated(uint16 newLowLatencyDelay);
}

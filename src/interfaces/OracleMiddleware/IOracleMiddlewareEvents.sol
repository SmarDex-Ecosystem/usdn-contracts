// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

/**
 * @title IOracleMiddlewareEvents
 * @notice Events for the oracle middleware
 */
interface IOracleMiddlewareEvents {
    /**
     * @notice Emitted when the time elapsed limit is updated
     * @param newTimeElapsedLimit The new limit
     */
    event TimeElapsedLimitUpdated(uint256 newTimeElapsedLimit);

    /**
     * @notice Emitted when validation delay is updated
     * @param newValidationDelay The new validation delay
     */
    event ValidationDelayUpdated(uint256 newValidationDelay);

    /**
     * @notice Emitted when recent price delay is updated
     * @param newDelay The new recent price delay
     */
    event RecentPriceDelayUpdated(uint64 newDelay);

    /**
     * @notice Emitted when the confidence ratio is updated
     * @param newConfRatio The new confidence ratio
     */
    event ConfRatioUpdated(uint256 newConfRatio);

    /**
     * @notice Emitted when the penalty is updated
     * @param newPenaltyBps The new penalty
     */
    event PenaltyBpsUpdated(uint16 newPenaltyBps);
}

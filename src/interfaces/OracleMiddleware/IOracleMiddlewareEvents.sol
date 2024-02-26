// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.0;

/**
 * @title IOracleMiddlewareEvents
 * @notice Events for the oracle middleware
 */
interface IOracleMiddlewareEvents {
    /**
     * @notice Emitted when the time elapsed limit is updated.
     * @param newTimeElapsedLimit The new limit.
     */
    event TimeElapsedLimitUpdated(uint256 newTimeElapsedLimit);

    /**
     * @notice Emitted when validation delay is updated.
     * @param newValidationDelay The new validation delay.
     */
    event ValidationDelayUpdated(uint256 newValidationDelay);

    /**
     * @notice Emitted when recent price delay is updated.
     * @param newDelay The new recent price delay.
     */
    event RecentPriceDelayUpdated(uint256 newDelay);
}

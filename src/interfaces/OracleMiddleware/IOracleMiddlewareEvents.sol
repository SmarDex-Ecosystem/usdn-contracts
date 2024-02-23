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
}

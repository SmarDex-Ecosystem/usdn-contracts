// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import { IOracleMiddlewareWithPyth } from "./IOracleMiddlewareWithPyth.sol";

/**
 * @title Oracle Middleware interface
 * @notice Same as the default oracle middleware, with added support for Redstone
 */
interface IOracleMiddlewareWithRedstone is IOracleMiddlewareWithPyth {
    /* -------------------------------------------------------------------------- */
    /*                              Generic features                              */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice Gets the penalty for using a non-Pyth price with low latency oracle (in basis points)
     * @return penaltyBps_ The penalty (in basis points).
     */
    function getPenaltyBps() external view returns (uint16 penaltyBps_);

    /* -------------------------------------------------------------------------- */
    /*                               Owner features                               */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice Sets the Redstone recent price delay.
     * @param newDelay The maximum age of a price to be considered recent.
     */
    function setRedstoneRecentPriceDelay(uint48 newDelay) external;

    /**
     * @notice Sets the penalty (in basis points).
     * @param newPenaltyBps The new penalty.
     */
    function setPenaltyBps(uint16 newPenaltyBps) external;
}

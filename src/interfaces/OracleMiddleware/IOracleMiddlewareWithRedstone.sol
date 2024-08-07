// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import { IOracleMiddleware } from "./IOracleMiddleware.sol";

/**
 * @title Oracle Middleware interface
 * @notice Same as the default oracle middleware, with added support for Redstone
 */
interface IOracleMiddlewareWithRedstone is IOracleMiddleware {
    /* -------------------------------------------------------------------------- */
    /*                              Generic features                              */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice Getter for the penalty value
     * @return The penalty basis points
     */
    function getPenaltyBps() external view returns (uint16);

    /* -------------------------------------------------------------------------- */
    /*                               Owner features                               */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice Set the redstone recent price delay
     * @param newDelay The maximum age of a recent price to be considered valid
     */
    function setRedstoneRecentPriceDelay(uint48 newDelay) external;

    /**
     * @notice Set the penalty basis points
     * @param newPenaltyBps The new penalty basis points
     */
    function setPenaltyBps(uint16 newPenaltyBps) external;
}

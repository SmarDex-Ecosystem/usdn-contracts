// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import { IOracleMiddleware } from "./IOracleMiddleware.sol";
import { IOracleMiddlewareErrors } from "./IOracleMiddlewareErrors.sol";
import { IOracleMiddlewareEvents } from "./IOracleMiddlewareEvents.sol";

/**
 * @title Oracle Middleware interface
 * @notice The oracle middleware is a contract that is called by the USDN protocol to validate price data. Using a
 * middleware allows the protocol to later upgrade to a new oracle logic without having to modify the vault contract
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

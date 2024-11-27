// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import { IBaseOracleMiddleware } from "./IBaseOracleMiddleware.sol";
import { IChainlinkOracle } from "./IChainlinkOracle.sol";
import { IOracleMiddlewareErrors } from "./IOracleMiddlewareErrors.sol";
import { IOracleMiddlewareEvents } from "./IOracleMiddlewareEvents.sol";
import { IPythOracle } from "./IPythOracle.sol";

/**
 * @title Oracle Middleware interface
 * @notice The oracle middleware is a contract that is called by the USDN protocol to validate price data. Using a
 * middleware allows the protocol to later upgrade to a new oracle logic without having to modify the vault contract
 */
interface IOracleMiddleware is
    IChainlinkOracle,
    IPythOracle,
    IBaseOracleMiddleware,
    IOracleMiddlewareErrors,
    IOracleMiddlewareEvents
{
    /* -------------------------------------------------------------------------- */
    /*                                    Roles                                   */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice The admin role's signature
     * @return Get the role signature
     */
    function ADMIN_ROLE() external pure returns (bytes32);

    /* -------------------------------------------------------------------------- */
    /*                                  Constants                                 */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice Denominator for the confidence ratio, will give us a 0.01% basis point
     * @return The BPS divisor
     */
    function BPS_DIVISOR() external pure returns (uint16);

    /**
     * @notice Maximum value for `_confRatioBps`
     * @return The max allowed confidence ratio
     */
    function MAX_CONF_RATIO() external pure returns (uint16);

    /* -------------------------------------------------------------------------- */
    /*                              Generic features                              */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice Getter for the confidence ratio
     * @dev This ratio is used to apply a specific portion of the confidence interval
     * provided by an oracle, which is used to adjust the precision of predictions or estimations
     * @return The confidence ratio basis points
     */
    function getConfRatioBps() external view returns (uint16);

    /* -------------------------------------------------------------------------- */
    /*                               Owner features                               */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice Set confidence ratio (admin)
     * @param newConfRatio the new confidence ratio
     * @dev New value should be lower than the max confidence ratio
     */
    function setConfRatio(uint16 newConfRatio) external;

    /**
     * @notice Set the elapsed time tolerated before we consider the price invalid for the chainlink oracle
     * @param newTimeElapsedLimit The new time elapsed limit
     */
    function setChainlinkTimeElapsedLimit(uint256 newTimeElapsedLimit) external;

    /**
     * @notice Set the recent price delay
     * @param newDelay The maximum age of a recent price to be considered valid
     */
    function setPythRecentPriceDelay(uint64 newDelay) external;

    /**
     * @notice Set the validation delay (in seconds) between an action timestamp and the price
     * data timestamp used to validate that action
     * @param newValidationDelay The new validation delay
     */
    function setValidationDelay(uint256 newValidationDelay) external;

    /**
     * @notice Set the new low latency delay
     * @param newLowLatencyDelay The new low latency delay
     */
    function setLowLatencyDelay(uint16 newLowLatencyDelay) external;

    /**
     * @notice Withdraw the ether balance of this contract
     * @dev This contract can receive funds but is not designed to hold them
     * So this function can be used if there's an error and funds remain after a call
     * @param to The address to send the ether to
     */
    function withdrawEther(address to) external;
}

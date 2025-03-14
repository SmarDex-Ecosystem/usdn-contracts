// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import { ICommonOracleMiddleware } from "./ICommonOracleMiddleware.sol";

/**
 * @notice The oracle middleware is a contract that is used by the USDN protocol to validate price data.
 * Using a middleware allows the protocol to later upgrade to a new oracle logic without having to modify
 * the protocol's contracts.
 * @dev This middleware uses Pyth as low-latency oracle and Chainlink Data Feeds as fallback.
 */
interface IOracleMiddleware is ICommonOracleMiddleware {
    /* -------------------------------------------------------------------------- */
    /*                                  Constants                                 */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice Gets the denominator for the variables using basis points as a unit.
     * @return denominator_ The BPS divisor.
     */
    function BPS_DIVISOR() external pure returns (uint16 denominator_);

    /**
     * @notice Gets the maximum value for `_confRatioBps`.
     * @return ratio_ The max allowed confidence ratio.
     */
    function MAX_CONF_RATIO() external pure returns (uint16 ratio_);

    /* -------------------------------------------------------------------------- */
    /*                              Generic features                              */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice Gets the confidence ratio.
     * @dev This ratio is used to apply a specific portion of the confidence interval provided by an oracle, which is
     * used to adjust the precision of predictions or estimations.
     * @return ratio_ The confidence ratio (in basis points).
     */
    function getConfRatioBps() external view returns (uint16 ratio_);

    /* -------------------------------------------------------------------------- */
    /*                               Owner features                               */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice Sets the confidence ratio.
     * @dev The new value should be lower than {MAX_CONF_RATIO}.
     * @param newConfRatio the new confidence ratio.
     */
    function setConfRatio(uint16 newConfRatio) external;
}

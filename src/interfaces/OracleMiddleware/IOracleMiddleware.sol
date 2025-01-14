// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import { IUsdnProtocol } from "../UsdnProtocol/IUsdnProtocol.sol";
import { IBaseOracleMiddleware } from "./IBaseOracleMiddleware.sol";
import { IChainlinkOracle } from "./IChainlinkOracle.sol";
import { IOracleMiddlewareErrors } from "./IOracleMiddlewareErrors.sol";
import { IOracleMiddlewareEvents } from "./IOracleMiddlewareEvents.sol";
import { IPythOracle } from "./IPythOracle.sol";

/**
 * @notice The oracle middleware is a contract that is used by the USDN protocol to validate price data.
 * Using a middleware allows the protocol to later upgrade to a new oracle logic without having to modify
 * the protocol's contracts.
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
     * @notice Gets the admin role's signature.
     * @return role_ Get the role signature.
     */
    function ADMIN_ROLE() external pure returns (bytes32 role_);

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

    /**
     * @notice Sets the elapsed time tolerated before we consider the price from Chainlink invalid.
     * @param newTimeElapsedLimit The new time elapsed limit.
     */
    function setChainlinkTimeElapsedLimit(uint256 newTimeElapsedLimit) external;

    /**
     * @notice Sets the amount of time after which we do not consider a price as recent.
     * @param newDelay The maximum age of a price to be considered recent.
     */
    function setPythRecentPriceDelay(uint64 newDelay) external;

    /**
     * @notice Sets the validation delay (in seconds) between an action timestamp and the price
     * data timestamp used to validate that action.
     * @param newValidationDelay The new validation delay.
     */
    function setValidationDelay(uint256 newValidationDelay) external;

    /**
     * @notice Sets the new low latency delay.
     * @param newLowLatencyDelay The new low latency delay.
     * @param usdnProtocol The address of the USDN protocol.
     */
    function setLowLatencyDelay(uint16 newLowLatencyDelay, IUsdnProtocol usdnProtocol) external;

    /**
     * @notice Withdraws the ether balance of this contract.
     * @dev This contract can receive funds but is not designed to hold them.
     * So this function can be used if there's an error and funds remain after a call.
     * @param to The address to send the ether to.
     */
    function withdrawEther(address to) external;
}

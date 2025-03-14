// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import { IAccessControlDefaultAdminRules } from
    "@openzeppelin/contracts/access/extensions/IAccessControlDefaultAdminRules.sol";

import { IUsdnProtocol } from "../UsdnProtocol/IUsdnProtocol.sol";
import { IBaseOracleMiddleware } from "./IBaseOracleMiddleware.sol";
import { IOracleMiddlewareErrors } from "./IOracleMiddlewareErrors.sol";
import { IOracleMiddlewareEvents } from "./IOracleMiddlewareEvents.sol";

/// @notice This is the common middleware interface for all current middlewares.
interface ICommonOracleMiddleware is
    IBaseOracleMiddleware,
    IOracleMiddlewareErrors,
    IOracleMiddlewareEvents,
    IAccessControlDefaultAdminRules
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
    /*                               Owner features                               */
    /* -------------------------------------------------------------------------- */

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

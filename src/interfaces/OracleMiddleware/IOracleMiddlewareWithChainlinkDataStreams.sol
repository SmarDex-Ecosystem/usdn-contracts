// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import { IUsdnProtocol } from "../UsdnProtocol/IUsdnProtocol.sol";
import { IBaseOracleMiddleware } from "./IBaseOracleMiddleware.sol";
import { IChainlinkDataStreamsOracle } from "./IChainlinkDataStreamsOracle.sol";
import { IChainlinkOracle } from "./IChainlinkOracle.sol";
import { IOracleMiddlewareErrors } from "./IOracleMiddlewareErrors.sol";
import { IOracleMiddlewareEvents } from "./IOracleMiddlewareEvents.sol";
import { IPythOracle } from "./IPythOracle.sol";

/**
 * @title Interface For The Middleware And Oracle Related Contracts
 * @notice Used by the USDN protocol to validate price data. Using a middleware allows the protocol to later upgrade to
 * a new oracle logic without having to modify the protocol's contracts.
 */
interface IOracleMiddlewareWithChainlinkDataStreams is
    IChainlinkOracle,
    IPythOracle,
    IBaseOracleMiddleware,
    IOracleMiddlewareErrors,
    IOracleMiddlewareEvents,
    IChainlinkDataStreamsOracle
{
    /* -------------------------------------------------------------------------- */
    /*                                    Roles                                   */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice Gets the admin role's signature.
     * @return role_ The role signature.
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
     * @notice Sets the amount of time after which we do not consider a price as recent for pyth.
     * @param newDelay The maximum age of a price to be considered recent.
     */
    function setPythRecentPriceDelay(uint64 newDelay) external;

    /**
     * @notice Sets the amount of time after which we do not consider a price as recent for Chainlink.
     * @param newDelay The maximum age of a price to be considered recent.
     */
    function setDataStreamsRecentPriceDelay(uint64 newDelay) external;

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

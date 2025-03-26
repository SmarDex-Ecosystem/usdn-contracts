// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import { IChainlinkDataStreamsOracle } from "./IChainlinkDataStreamsOracle.sol";
import { ICommonOracleMiddleware } from "./ICommonOracleMiddleware.sol";

/**
 * @notice The oracle middleware is a contract that is used by the USDN protocol to validate price data.
 * Using a middleware allows the protocol to later upgrade to a new oracle logic without having to modify
 * the protocol's contracts.
 * @dev This middleware uses Chainlink Data Streams and Pyth as the low-latency oracle, and Chainlink Data Feeds as
 * fallback. For liquidations, either Pyth or Data Streams can be used. For validations, only Data Streams is accepted.
 */
interface IOracleMiddlewareWithDataStreams is ICommonOracleMiddleware, IChainlinkDataStreamsOracle {
    /* -------------------------------------------------------------------------- */
    /*                               Owner features                               */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice Sets the amount of time after which we do not consider a price as recent for Chainlink.
     * @param newDelay The maximum age of a price to be considered recent.
     */
    function setDataStreamsRecentPriceDelay(uint64 newDelay) external;
}

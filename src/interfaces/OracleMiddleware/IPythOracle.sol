// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import { IPyth } from "@pythnetwork/pyth-sdk-solidity/IPyth.sol";

import { IOracleMiddlewareErrors } from "../../interfaces/OracleMiddleware/IOracleMiddlewareErrors.sol";

interface IPythOracle is IOracleMiddlewareErrors {
    /**
     * @notice Gets the Pyth contract address.
     * @return pyth_ The Pyth contract address.
     */
    function getPyth() external view returns (IPyth pyth_);

    /**
     * @notice Gets the ID of the price feed queried by this contract.
     * @return feedId_ The Pyth price feed ID.
     */
    function getPythFeedId() external view returns (bytes32 feedId_);

    /**
     * @notice Gets the recent price delay.
     * @return recentPriceDelay_ The maximum age of a recent price to be considered valid.
     */
    function getPythRecentPriceDelay() external view returns (uint64 recentPriceDelay_);
}

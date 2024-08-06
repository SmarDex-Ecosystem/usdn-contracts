// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import { IPyth } from "@pythnetwork/pyth-sdk-solidity/IPyth.sol";

interface IPythOracle {
    /**
     * @notice Get ahead delay threshold for Pyth price feed
     * @return The ahead delay threshold in seconds
     */
    function PYTH_AHEAD_THRESHOLD() external view returns (uint8);

    /**
     * @notice Get the Pyth contract address
     * @return pyth_ The Pyth contract address
     */
    function getPyth() external view returns (IPyth pyth_);

    /**
     * @notice Get the Pyth price ID
     * @return feedId_ The Pyth price feed ID
     */
    function getPythFeedId() external view returns (bytes32 feedId_);

    /**
     * @notice Get the recent price delay
     * @return recentPriceDelay_ The maximum age of a recent price to be considered valid
     */
    function getPythRecentPriceDelay() external view returns (uint64 recentPriceDelay_);
}

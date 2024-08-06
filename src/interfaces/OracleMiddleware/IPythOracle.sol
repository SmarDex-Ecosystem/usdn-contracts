// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import { IPyth } from "@pythnetwork/pyth-sdk-solidity/IPyth.sol";

interface IPythOracle {
    /**
     * @notice Ahead threshold for Pyth, in seconds
     * @dev Pyth price updates can have a timestamp that exceeds the block.timestamp. In such a case, we accept that
     * price up to this offset in the future
     * @return The ahead threshold
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

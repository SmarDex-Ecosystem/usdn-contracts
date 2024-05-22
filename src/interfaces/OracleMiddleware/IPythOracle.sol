// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import { IPyth } from "@pythnetwork/pyth-sdk-solidity/IPyth.sol";

interface IPythOracle {
    /**
     * @notice Get the Pyth contract address
     * @return pyth_ The Pyth contract address
     */
    function getPyth() external view returns (IPyth pyth_);

    /**
     * @notice Get the Pyth price ID
     * @return priceID_ The Pyth price ID
     */
    function getPriceID() external view returns (bytes32 priceID_);

    /**
     * @notice Get the recent price delay
     * @return recentPriceDelay_ The maximum age of a recent price to be considered valid
     */
    function getRecentPriceDelay() external view returns (uint64 recentPriceDelay_);
}

// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.25;

/**
 * @title USDN Protocol Utils
 * @notice This library contains utility functions for the USDN protocol, and will not be deployed as an external lib
 */
library UsdnProtocolUtils {
    /**
     * @notice Convert a uint128 to an int256
     * @param x The value to convert
     * @return The converted value
     */
    function toInt256(uint128 x) internal pure returns (int256) {
        return int256(uint256(x));
    }
}

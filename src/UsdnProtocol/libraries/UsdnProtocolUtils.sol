// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.25;

library UsdnProtocolUtils {
    /**
     * @notice Convert a uint128 to an int256
     * @param x The value to convert
     * @return The converted value
     */
    function toInt256(uint128 x) public pure returns (int256) {
        return int256(uint256(x));
    }
}

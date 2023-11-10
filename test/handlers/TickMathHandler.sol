// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { TickMath } from "src/libraries/TickMath.sol";

/**
 * @title TickMathHandler
 * @notice Helper to get gas usage report
 */
contract TickMathHandler {
    function maxUsableTick(int24 tickSpacing) external pure returns (int24) {
        return TickMath.maxUsableTick(tickSpacing);
    }

    function minUsableTick(int24 tickSpacing) external pure returns (int24) {
        return TickMath.minUsableTick(tickSpacing);
    }

    function getPriceAtTick(int24 tick) external pure returns (uint256) {
        return TickMath.getPriceAtTick(tick);
    }

    function getTickAtPrice(uint256 price) external pure returns (int24) {
        return TickMath.getTickAtPrice(price);
    }

    function getClosestTickAtPrice(uint256 price) external pure returns (int24) {
        return TickMath.getClosestTickAtPrice(price);
    }
}

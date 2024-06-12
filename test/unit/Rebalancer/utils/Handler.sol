// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import { Test } from "forge-std/Test.sol";

import { IUsdnProtocol } from "src/interfaces/UsdnProtocol/IUsdnProtocol.sol";
import { Rebalancer } from "src/Rebalancer/Rebalancer.sol";

/**
 * @title RebalancerHandler
 * @dev Wrapper to aid in testing the rebalancer
 */
contract RebalancerHandler is Rebalancer, Test {
    constructor(IUsdnProtocol usdnProtocol) Rebalancer(usdnProtocol) { }

    /// @dev Sets the position version to the current one + 1
    function incrementPositionVersion() external {
        ++_positionVersion;
    }

    /**
     * @dev Sets the _lastLiquidatedVersion to the provided value
     * @param version The version to set
     */
    function setLastLiquidatedVersion(uint128 version) external {
        _lastLiquidatedVersion = version;
    }
}

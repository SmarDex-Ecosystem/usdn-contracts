// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

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
}

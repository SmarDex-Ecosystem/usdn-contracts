// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import { RebalancerFixture } from "./utils/Fixtures.sol";

/**
 * @custom:feature The {_calcPnlMultiplier} function of the rebalancer contract
 * @custom:background Given a rebalancer contract
 */
contract TestRebalancerCalcPnlMultiplier is RebalancerFixture {
    uint256 MULTIPLIER_FACTOR;

    function setUp() public {
        super._setUp();
        MULTIPLIER_FACTOR = rebalancer.MULTIPLIER_FACTOR();
    }

    /**
     * @custom:scenario Trying to calculate a PnL multiplier with an open amount of 0
     * @custom:when 0 is provided as the open amount
     * @custom:then 0 is returned
     */
    function test_calcPnlMultiplierWithZeroAmount() external {
        uint256 multiplier = rebalancer.i_calcPnlMultiplier(0, 2000 ether);
        assertEq(multiplier, 0, "The result should be 0");
    }

    /**
     * @custom:scenario Calculate a PnL multiplier
     * @custom:when 2000 ether is given as the open amount
     * @custom:and 2200 ether is given as the value
     * @custom:then A multiplier of 1.1x is returned
     * @custom:when 2000 ether is given as the open amount
     * @custom:and 1800 ether is given as the value
     * @custom:then A multiplier of ~0.9x is returned
     * @custom:when 2000 ether is given as the open amount
     * @custom:and 0 is given as the value
     * @custom:then 0 is returned
     */
    function test_calcPnlMultiplier() external {
        uint256 multiplier = rebalancer.i_calcPnlMultiplier(2000 ether, 2200 ether);
        assertEq(multiplier, MULTIPLIER_FACTOR * 11 / 10, "The result should be 1.1x");

        multiplier = rebalancer.i_calcPnlMultiplier(2000 ether, 1800 ether);
        assertEq(multiplier, MULTIPLIER_FACTOR * 9 / 10, "The result should be 0.9x");

        multiplier = rebalancer.i_calcPnlMultiplier(2000 ether, 0);
        assertEq(multiplier, 0, "The result should be 0");
    }
}

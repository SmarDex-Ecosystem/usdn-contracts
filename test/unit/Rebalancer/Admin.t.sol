// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

import { RebalancerFixture } from "test/unit/Rebalancer/utils/Fixtures.sol";
import { ADMIN } from "test/utils/Constants.sol";

/**
 * @custom:feature The admin functions of the order manager
 * @custom:background Given an order manager instance
 */
contract TestRebalancerAdmin is RebalancerFixture {
    int256 internal _closeImbalanceLimitBps;

    function setUp() public {
        super._setUp();
        _closeImbalanceLimitBps = usdnProtocol.getCloseExpoImbalanceLimitBps();
    }

    /**
     * @custom:scenario Call setTargetLongImbalanceBps with the caller not being the owner
     * @custom:when setTargetLongImbalanceBps is called
     * @custom:then The call reverts with an OwnableUnauthorizedAccount error
     */
    function test_RevertWhen_SetTargetLongImbalanceBpsCallerIsNotOwner() external {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        rebalancer.setTargetLongImbalanceBps(0);
    }

    /**
     * @custom:scenario Call setTargetLongImbalanceBps with a value that is too high
     * @custom:given The caller being the owner
     * @custom:when setTargetLongImbalanceBps is called with a value that is higher than the close imbalance limit
     * @custom:then The call reverts with an RebalancerImbalanceTargetTooHigh error
     */
    function test_RevertWhen_setTargetLongImbalanceBpsTooHigh() external {
        vm.prank(ADMIN);
        vm.expectRevert(RebalancerImbalanceTargetTooHigh.selector);
        rebalancer.setTargetLongImbalanceBps(_closeImbalanceLimitBps);
    }

    /**
     * @custom:scenario setTargetLongImbalanceBps is called and the value is updated
     * @custom:given The caller being the owner
     * @custom:when setTargetLongImbalanceBps is called
     * @custom:then The _targetLongImbalanceBps value is updated
     * @custom:and an TargetLongImbalanceUpdated event is emitted
     */
    function test_setTargetLongImbalanceBps() external {
        vm.expectEmit();
        emit TargetLongImbalanceUpdated(_closeImbalanceLimitBps - 1);
        vm.prank(ADMIN);
        rebalancer.setTargetLongImbalanceBps(_closeImbalanceLimitBps - 1);

        assertEq(
            rebalancer.getTargetLongImbalanceBps(),
            _closeImbalanceLimitBps - 1,
            "The target imbalance should have been updated"
        );
    }
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { RebalancerFixture } from "./utils/Fixtures.sol";

/**
 * @custom:feature The {_refundEther} function of the rebalancer contract
 * @custom:background Given a rebalancer contract with a 1 ether balance
 */
contract TestRebalancerRefundEther is RebalancerFixture {
    uint256 constant AMOUNT = 1 ether;

    bool revertOnReceive;

    function setUp() public {
        super._setUp();
        vm.deal(address(rebalancer), AMOUNT);
    }

    /**
     * @custom:scenario Send the ether in the rebalancer to the caller
     * @custom:when The {_refundEther} function is called
     * @custom:then The user should have received the rebalancer's balance
     */
    function test_refundEther() public {
        uint256 balanceBefore = address(this).balance;
        rebalancer.i_refundEther();

        assertEq(address(this).balance, balanceBefore + AMOUNT, "The wrong amount of ether was refunded");
    }

    /**
     * @custom:scenario Reverts if the `to` address cannot receive ether
     * @custom:given The `to` address is a contract that reverts when receiving ether
     * @custom:when The {_refundEther} function is called
     * @custom:then The call should revert with a {RebalancerEtherRefundFailed} error
     */
    function test_RevertWhen_refundEtherFails() public {
        revertOnReceive = true;

        vm.expectRevert(RebalancerEtherRefundFailed.selector);
        rebalancer.i_refundEther();
    }

    receive() external payable {
        require(!revertOnReceive, "revert on receive");
    }
}

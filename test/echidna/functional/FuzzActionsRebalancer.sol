// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import { Setup } from "../Setup.sol";

contract FuzzActionsRebalancer is Setup {
    /* -------------------------------------------------------------------------- */
    /*                               Rebalancer                                   */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice RBLCR-0
     */
    function initiateDepositRebalancer(uint88 amountRand, uint256 destRand) public {
        destRand = bound(destRand, 0, destinationsToken[address(wsteth)].length - 1);
        address dest = destinationsToken[address(wsteth)][destRand];

        wsteth.mintAndApprove(msg.sender, amountRand, address(rebalancer), amountRand);

        RebalancerSnapshot memory balancesBefore = getRebalancerSnapshot(dest);

        vm.prank(msg.sender);
        try rebalancer.initiateDepositAssets(amountRand, dest) {
            assert(msg.sender.balance == balancesBefore.senderEth);
            assert(address(rebalancer).balance == balancesBefore.rebalancerEth);
            assert(wsteth.balanceOf(address(rebalancer)) == balancesBefore.rebalancerWsteth + amountRand);
            assert(wsteth.balanceOf(msg.sender) == balancesBefore.senderWsteth - amountRand);
            if (dest != msg.sender) {
                assert(address(dest).balance == balancesBefore.toEth);
                assert(wsteth.balanceOf(dest) == balancesBefore.toWsteth);
            }
        } catch (bytes memory err) {
            _checkErrors(err, INITIATE_OPEN_ERRORS);
        }
    }
}

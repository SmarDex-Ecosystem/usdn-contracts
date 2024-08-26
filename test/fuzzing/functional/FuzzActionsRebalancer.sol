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
    function initiateDepositRebalancer(uint256 amountRand, uint256 destRand) public {
        destRand = bound(destRand, 0, destinationsToken[address(wsteth)].length - 1);
        amountRand = bound(amountRand, 0, type(uint88).max);
        address dest = destinationsToken[address(wsteth)][destRand];

        RebalancerSnapshot memory balancesBefore = getRebalancerSnapshot(dest);

        vm.prank(msg.sender);
        try rebalancer.initiateDepositAssets(uint88(amountRand), dest) {
            // assert(msg.sender.balance == balancesBefore.senderEth);
            // assert(address(rebalancer).balance == balancesBefore.rebalancerEth);
            // assert(wsteth.balanceOf(address(rebalancer)) == balancesBefore.rebalancerWsteth + amountRand);
            // assert(wsteth.balanceOf(msg.sender) == balancesBefore.senderWsteth - amountRand);
            // if (dest != msg.sender) {
            //     assert(address(dest).balance == balancesBefore.toEth);
            //     assert(wsteth.balanceOf(dest) == balancesBefore.toWsteth);
            // }
        } catch (bytes memory err) {
            _checkErrors(err, INITIATE_OPEN_ERRORS);
        }
    }
}

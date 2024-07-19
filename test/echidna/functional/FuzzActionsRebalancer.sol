// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import { Setup } from "../Setup.sol";

contract FuzzActionsRebalancer is Setup {
    /* -------------------------------------------------------------------------- */
    /*                               Rebalancer                                   */
    /* -------------------------------------------------------------------------- */
    function initiateDepositRebalancer(uint88 amountRand, address destRand) public {
        require(destRand != address(0), "FuzzActionsRebalancer: Invalid destination address");

        uint88 amount = uint88(bound(amountRand, rebalancer.getMinAssetDeposit(), type(uint88).max));

        vm.prank(msg.sender);
        wsteth.mintAndApprove(msg.sender, amount, address(rebalancer), amount);

        RebalancerSnapshot memory balancesBefore = getBalancesRebalancer(destRand);

        vm.prank(msg.sender);
        try rebalancer.initiateDepositAssets(amount, destRand) {
            assert(msg.sender.balance == balancesBefore.senderEth);
            assert(address(rebalancer).balance == balancesBefore.rebalancerEth);
            assert(wsteth.balanceOf(address(rebalancer)) == balancesBefore.rebalancerWsteth + amount);
            assert(wsteth.balanceOf(msg.sender) == balancesBefore.senderWsteth - amount);
            if (destRand != msg.sender) {
                assert(address(destRand).balance == balancesBefore.toEth);
                assert(wsteth.balanceOf(destRand) == balancesBefore.toWsteth);
            }
        } catch (bytes memory err) {
            _checkErrors(err, INITIATE_OPEN_ERRORS);
        }
    }
}

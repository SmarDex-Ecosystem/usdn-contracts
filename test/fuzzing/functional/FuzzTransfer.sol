// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import { Setup } from "../Setup.sol";
import { Utils } from "../helpers/Utils.sol";

import { IUsdn } from "../../../src/interfaces/Usdn/IUsdn.sol";

contract FuzzTransfer is Setup, Utils {
    function transfer(uint256 tokenRand, uint256 amountRand, uint256 destRand) public {
        address[3] memory tokens = [address(0), address(usdn), address(wsteth)];
        tokenRand = bound(tokenRand, 0, tokens.length - 1);
        address token = tokens[tokenRand];

        address payable dest = boundDestination(destinationsToken[token], users, true, destRand);

        if (token == address(0)) {
            amountRand = bound(amountRand, 0, address(msg.sender).balance);
            vm.deal(msg.sender, amountRand);
            vm.prank(msg.sender);
            dest.transfer(amountRand);
        } else if (token == address(usdn)) {
            amountRand = bound(amountRand, 0, usdn.sharesOf(msg.sender));
            usdn.mintShares(msg.sender, amountRand);
            vm.prank(msg.sender);
            usdn.transferShares(dest, amountRand);
        } else {
            amountRand = bound(amountRand, 0, wsteth.balanceOf(msg.sender));
            wsteth.mint(msg.sender, amountRand);
            vm.prank(msg.sender);
            wsteth.transfer(dest, amountRand);
        }
    }
}

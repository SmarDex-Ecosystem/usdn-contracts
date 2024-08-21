// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import { Setup } from "../Setup.sol";

import { IUsdnProtocolTypes } from "../../../src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract FuzzTransfer is Setup {
    function transfer(uint256 tokenRand, uint256 amountRand, uint256 destRand) public {
        address[2] memory users = [DEPLOYER, ATTACKER];
        address[4] memory tokens = [address(0), address(sdex), address(weth), address(wsteth)];

        destRand = bound(destRand, 0, users.length - 1);
        address payable dest = payable(users[destRand]);

        while (dest == msg.sender) {
            destRand = bound(destRand, 0, users.length - 1);
            dest = payable(users[destRand]);
        }

        tokenRand = bound(tokenRand, 0, tokens.length - 1);
        address token = tokens[tokenRand];

        if (token == address(0)) {
            amountRand = bound(amountRand, 0, address(msg.sender).balance);
            vm.prank(msg.sender);
            dest.transfer(amountRand);
        } else {
            amountRand = bound(amountRand, 0, IERC20(token).balanceOf(address(msg.sender)));
            vm.prank(msg.sender);
            IERC20(token).transfer(dest, amountRand);
        }
    }
}

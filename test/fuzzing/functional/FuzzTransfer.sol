// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import { Setup } from "../Setup.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IUsdn } from "../../../src/interfaces/Usdn/IUsdn.sol";

contract FuzzTransfer is Setup {
    function transfer(uint256 tokenRand, uint256 amountRand, uint256 destRand) public {
        address[3] memory recipients = [address(wstEthOracleMiddleware), address(usdnProtocol), address(rebalancer)];
        address[3] memory tokens = [address(0), address(usdn), address(wsteth)];

        address[] memory filteredUsers = new address[](recipients.length + users.length - 1);
        uint256 index = 0;

        for (uint256 i = 0; i < users.length; i++) {
            if (users[i] != msg.sender) {
                filteredUsers[index] = users[i];
                index++;
            }
        }

        for (uint256 i = 0; i < recipients.length; i++) {
            filteredUsers[index + i] = recipients[i];
        }

        destRand = bound(destRand, 0, filteredUsers.length - 1);
        address payable dest = payable(filteredUsers[destRand]);

        tokenRand = bound(tokenRand, 0, tokens.length - 1);
        address token = tokens[tokenRand];

        if (token == address(0)) {
            amountRand = bound(amountRand, 0, address(msg.sender).balance);
            vm.prank(msg.sender);
            dest.transfer(amountRand);
        } else if (token == address(usdn)) {
            amountRand = bound(amountRand, 0, IUsdn(token).sharesOf(msg.sender));
            vm.prank(msg.sender);
            IUsdn(token).transferShares(dest, amountRand);
        } else {
            amountRand = bound(amountRand, 0, IERC20(token).balanceOf(msg.sender));
            vm.prank(msg.sender);
            IERC20(token).transfer(dest, amountRand);
        }
    }
}

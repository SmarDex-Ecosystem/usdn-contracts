// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { Script } from "forge-std/Script.sol";

import { WstETH } from "test/utils/WstEth.sol";

contract Fork is Script {
    function run() external {
        vm.startBroadcast(vm.envAddress("DEPLOYER_ADDRESS"));

        // Get the address of the wstETH token
        address payable wstETHAddress = payable(vm.envAddress("WSTETH_ADDRESS"));
        WstETH wstETH = WstETH(wstETHAddress);

        // Calculate the amount of ETH needed to mint the required amount of wstETH
        uint256 depositAmount = vm.envOr("INIT_DEPOSIT_AMOUNT", uint256(0));
        uint256 longAmount = vm.envOr("INIT_LONG_AMOUNT", uint256(0));
        uint256 stEthPerWstEth = wstETH.stEthPerToken();
        // Add 1000 wei to account for rounding errors
        uint256 ethAmount = (depositAmount + longAmount + 1000) * stEthPerWstEth / 1 ether;

        // Mint wstETH
        if (depositAmount + longAmount > 0) {
            (bool result,) = address(wstETH).call{ value: ethAmount }(hex"");
            require(result, "Fork: failed to mint wstETH");
        }

        vm.stopBroadcast();
    }
}

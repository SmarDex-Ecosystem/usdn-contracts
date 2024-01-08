// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { Script } from "forge-std/Script.sol";

import { WstETH } from "test/utils/WstEth.sol";

contract Fork is Script {
    function run() external {
        vm.startBroadcast(vm.envAddress("DEPLOYER_ADDRESS"));

        address payable wstETHAddress = payable(vm.envOr("WSTETH_ADDRESS", address(0)));
        WstETH wstETH;
        if (wstETHAddress != address(0)) {
            wstETH = WstETH(wstETHAddress);
        } else {
            wstETH = new WstETH();
            wstETHAddress = payable(address(wstETH));
        }
        (bool result,) = address(wstETH).call{ value: 3 ether }(hex"");
        require(result, "Fork: failed to mint wstETH");

        vm.stopBroadcast();
    }
}

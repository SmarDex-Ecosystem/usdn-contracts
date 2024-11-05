// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { Script } from "forge-std/Script.sol";

import { pUsdn } from "../src/Usdn/pUsdn.sol";

contract DeployPUsdn is Script {
    function run() external returns (pUsdn pUsdn_) {
        address deployerAddress = vm.envAddress("DEPLOYER_ADDRESS");

        vm.broadcast(deployerAddress);
        pUsdn_ = new pUsdn();
    }
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { Script } from "forge-std/Script.sol";

import { pUsdn } from "../src/Usdn/pUsdn.sol";

contract DeployPUsdn is Script {
    function run() external returns (pUsdn pUsdn_) {
        address deployerAddress = vm.envAddress("DEPLOYER_ADDRESS");

        vm.broadcast(deployerAddress);
        pUsdn_ = new pUsdn(0xB0470cF15B22a6A32c49a7C20E3821B944A76058, 0x1E3e1128F6bC2264a19D7a065982696d356879c5);
    }
}

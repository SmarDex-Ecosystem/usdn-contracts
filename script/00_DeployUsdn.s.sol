// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { Script } from "forge-std/Script.sol";

import { Usdn } from "../src/Usdn/Usdn.sol";

contract DeployUsdn is Script {
    function run() external returns (Usdn Usdn_) {
        address deployerAddress = vm.envAddress("DEPLOYER_ADDRESS");
        uint64 nounce = vm.getNonce(deployerAddress);

        require(block.chainid == 1, "DeployUsdn: not allowed in test environment, use 02_Deploy.s.sol instead");
        require(nounce == 0, "Nounce must be 0");

        vm.broadcast(deployerAddress);
        Usdn_ = new Usdn(address(0), address(0));
    }
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { Script } from "forge-std/Script.sol";

import { Usdn } from "../src/Usdn/Usdn.sol";

contract DeployUsdn is Script {
    function run() external returns (Usdn Usdn_) {
        address deployerAddress = vm.envAddress("DEPLOYER_ADDRESS");
        address safeAddress = vm.envAddress("SAFE_ADDRESS");

        uint64 nonce = vm.getNonce(deployerAddress);
        require(nonce == 0, "Nonce must be 0");

        vm.startBroadcast(deployerAddress);
        Usdn_ = new Usdn(address(0), address(0));

        Usdn_.grantRole(Usdn_.DEFAULT_ADMIN_ROLE(), safeAddress);
        Usdn_.renounceRole(Usdn_.DEFAULT_ADMIN_ROLE(), deployerAddress);

        vm.stopBroadcast();
    }
}

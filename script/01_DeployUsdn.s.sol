// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { Script } from "forge-std/Script.sol";

import { Usdn } from "../src/Usdn/Usdn.sol";

contract DeployUsdn is Script {
    function run() external returns (Usdn Usdn_) {
        bool isProdEnv = block.chainid != vm.envOr("FORK_CHAIN_ID", uint256(31_337));
        require(isProdEnv, "DeployUsdn: not allowed in test environment, use 02_Deploy.s.sol instead");

        vm.startBroadcast(vm.envAddress("DEPLOYER_ADDRESS"));
        Usdn_ = new Usdn(address(0), address(0));
        vm.stopBroadcast();
    }
}

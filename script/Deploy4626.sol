// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { Script } from "forge-std/Script.sol";

import { WusdnVault } from "../src/utils/WusdnVault.sol";

contract DeploySetRebaseHandlerManager is Script {
    function run() external returns (WusdnVault wusdn4626) {
        vm.broadcast();
        wusdn4626 = new WusdnVault();
    }
}

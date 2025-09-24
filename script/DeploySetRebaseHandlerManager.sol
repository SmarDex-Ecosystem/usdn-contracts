// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { Script } from "forge-std/Script.sol";

import { Usdn } from "../src/Usdn/Usdn.sol";
import { SetRebaseHandlerManager } from "../src/utils/SetRebaseHandlerManager.sol";

contract DeploySetRebaseHandlerManager is Script {
    address constant USDN_MAINNET = 0xde17a000BA631c5d7c2Bd9FB692EFeA52D90DEE2;
    address constant SAFE_MAINNET = 0x1E3e1128F6bC2264a19D7a065982696d356879c5;

    function run() external returns (SetRebaseHandlerManager setRebaseHandlerManager_) {
        vm.broadcast();
        setRebaseHandlerManager_ = new SetRebaseHandlerManager(Usdn(USDN_MAINNET), SAFE_MAINNET);
    }
}

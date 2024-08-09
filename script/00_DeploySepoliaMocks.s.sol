// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { Script } from "forge-std/Script.sol";

import { MockFastGasGwei } from "../src/OracleMiddleware/mock/MockFastGasGwei.sol";
import { Sdex } from "../src/utils/sepolia/tokens/Sdex.sol";
import { WstETH } from "../src/utils/sepolia/tokens/WstETH.sol";

contract DeploySepoliaMocks is Script {
    function run(address deployer, uint256 wstethNeeded)
        external
        returns (Sdex Sdex_, WstETH WstETH_, MockFastGasGwei MockFastGasGwei_)
    {
        vm.startBroadcast(deployer);

        Sdex_ = new Sdex();
        WstETH_ = new WstETH();
        MockFastGasGwei_ = new MockFastGasGwei();

        // mint wstETH to deployer
        WstETH_.mint(deployer, wstethNeeded);

        vm.stopBroadcast();
    }
}

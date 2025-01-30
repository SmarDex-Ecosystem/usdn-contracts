// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { Script } from "forge-std/Script.sol";

import { Usdn } from "../src/Usdn/Usdn.sol";
import { IWusdn } from "../src/interfaces/Usdn/IWusdn.sol";
import { WusdnAdaptor } from "../src/utils/WusdnAdaptor.sol";

contract DeployWusdnAdaptor is Script {
    IWusdn constant WUSDN = IWusdn(0x99999999999999Cc837C997B882957daFdCb1Af9);

    function run() external returns (WusdnAdaptor wusdnAdaptor) {
        string memory etherscanApiKey = vm.envOr("ETHERSCAN_API_KEY", string("XXXXXXXXXXXXXXXXX"));
        vm.setEnv("ETHERSCAN_API_KEY", etherscanApiKey);

        vm.startBroadcast();

        wusdnAdaptor = new WusdnAdaptor(WUSDN);

        vm.stopBroadcast();
    }
}

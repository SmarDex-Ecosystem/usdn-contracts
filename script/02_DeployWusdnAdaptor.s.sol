// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { Script } from "forge-std/Script.sol";

import { IWusdn } from "../src/interfaces/Usdn/IWusdn.sol";
import { WusdnBalancerAdaptor } from "../src/utils/WusdnBalancerAdaptor.sol";

contract DeployWusdnAdaptor is Script {
    IWusdn constant WUSDN = IWusdn(0x99999999999999Cc837C997B882957daFdCb1Af9);

    function run() external returns (WusdnBalancerAdaptor wusdnBalancerAdaptor_) {
        vm.startBroadcast();

        wusdnBalancerAdaptor_ = new WusdnBalancerAdaptor(WUSDN);

        vm.stopBroadcast();
    }
}

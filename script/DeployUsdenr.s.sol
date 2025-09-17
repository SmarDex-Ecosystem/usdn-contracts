// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { Script } from "forge-std/Script.sol";

import { Usdnr } from "../src/Usdn/Usdnr.sol";
import { IUsdn } from "../src/interfaces/Usdn/IUsdn.sol";

contract DeployUsdnr is Script {
    function run(IUsdn usdn) external returns (address usdnr_) {
        vm.broadcast();
        usdnr_ = address(new Usdnr(usdn));
    }
}

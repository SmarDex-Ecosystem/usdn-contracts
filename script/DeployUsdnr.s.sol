// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { Script } from "forge-std/Script.sol";

import { Usdnr } from "../src/Usdn/Usdnr.sol";
import { IUsdn } from "../src/interfaces/Usdn/IUsdn.sol";

contract DeployUsdnr is Script {
    /**
     * @notice Deploy the USDNr contract
     * @param usdn The address of the USDN contract
     * @return usdnr_ The address of the deployed USDNr contract
     */
    function run(IUsdn usdn) external returns (Usdnr usdnr_) {
        vm.broadcast();
        usdnr_ = new Usdnr(usdn);
    }
}

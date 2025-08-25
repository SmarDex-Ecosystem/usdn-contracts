// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { Script } from "forge-std/Script.sol";

import { LiquidationRewardsManagerWstEth } from
    "../../src/LiquidationRewardsManager/LiquidationRewardsManagerWstEth.sol";
import { LiquidationRewardsManagerWusdn } from "../../src/LiquidationRewardsManager/LiquidationRewardsManagerWusdn.sol";

import { WstEthOracleMiddlewareWithPyth } from "../../src/OracleMiddleware/WstEthOracleMiddlewareWithPyth.sol";
import { WusdnToEthOracleMiddlewareWithPyth } from "../../src/OracleMiddleware/WusdnToEthOracleMiddlewareWithPyth.sol";
import { Rebalancer } from "../../src/Rebalancer/Rebalancer.sol";
import { Usdn } from "../../src/Usdn/Usdn.sol";
import { UsdnNoRebase } from "../../src/Usdn/UsdnNoRebase.sol";
import { IWusdn } from "../../src/interfaces/Usdn/IWusdn.sol";
import { IUsdnProtocol } from "../../src/interfaces/UsdnProtocol/IUsdnProtocol.sol";
import { DeployUsdnWstethFork } from "./01_DeployUsdnWstethUsdFork_Long.s.sol";
import { DeployUsdnWusdnFork } from "./01_DeployUsdnWusdnEthFork_Short.s.sol";

struct DeployedUsdnAndShortdn {
    // USDN START
    WstEthOracleMiddlewareWithPyth wstEthOracleMiddleware_;
    LiquidationRewardsManagerWstEth liquidationRewardsManagerWstEth_;
    Rebalancer rebalancerUsdn_;
    Usdn usdn_;
    IWusdn wusdn_;
    IUsdnProtocol usdnProtocolUsdn_;
    // SHORTDN START
    WusdnToEthOracleMiddlewareWithPyth wusdnToEthOracleMiddleware_;
    LiquidationRewardsManagerWusdn liquidationRewardsManagerWusdn_;
    Rebalancer rebalancerShortdn_;
    UsdnNoRebase usdnNoRebaseShortdn_;
    IUsdnProtocol usdnProtocolShortdn_;
}

contract DeployUsdnAndShortdn is Script {
    /**
     * @notice Deploy the USDN ecosystem with the WstETH as underlying and the SHORTDN ecosystem with the WUSDN as
     * underlying
     */
    function run() external {
        DeployUsdnWstethFork deployUsdnWstethFork = new DeployUsdnWstethFork();
        // deployUsdnWstethFork.preRun();
        (,,,,, IUsdnProtocol usdnProtocol_) = deployUsdnWstethFork.run();
        // deployUsdnWstethFork.postRun(usdnProtocol_);

        // vm.setEnv("UNDERLYING_ADDRESS_WUSDN", vm.toString(address(deployedUsdnAndShortdn.wusdn_)));

        // DeployUsdnWusdnFork deployUsdnWusdnFork = new DeployUsdnWusdnFork();
        // (
        //     deployedUsdnAndShortdn.wusdnToEthOracleMiddleware_,
        //     deployedUsdnAndShortdn.liquidationRewardsManagerWusdn_,
        //     deployedUsdnAndShortdn.rebalancerShortdn_,
        //     deployedUsdnAndShortdn.usdnNoRebaseShortdn_,
        //     deployedUsdnAndShortdn.usdnProtocolShortdn_
        // ) = deployUsdnWusdnFork.preRunAndRun();
    }
}

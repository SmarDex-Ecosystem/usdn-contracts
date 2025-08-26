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

import { DeployShortdnFork } from "./DeployShortdnFork.s.sol";
import { DeployUsdnFork } from "./DeployUsdnFork.s.sol";

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

contract DeployUsdnAndShortdnFork is Script {
    /**
     * @notice Deploy the USDN ecosystem with the WstETH as underlying and the SHORTDN ecosystem with the WUSDN as
     * underlying
     */
    function run() external {
        // DEPLOY USDN (LONG ETH)
        DeployUsdnFork deployUsdnFork = new DeployUsdnFork();
        (,,, Usdn usdn, IWusdn wusdn, IUsdnProtocol protocol) = deployUsdnFork.run();

        // DEFINE FUTURE SHORTDN COLLATERAL AKA WUSDN OF ALREADY DEPLOYED USDN PROTOCOL
        vm.setEnv("UNDERLYING_ADDRESS_WUSDN", vm.toString(address(wusdn)));

        // WRAP USDN INTO WUSDN AND APPROVE IT TO THE SHORTDN PROTOCOL
        vm.startBroadcast(msg.sender);
        usdn.approve(address(wusdn), type(uint256).max);
        wusdn.wrap(usdn.balanceOf(msg.sender));
        wusdn.approve(address(protocol), type(uint256).max);
        vm.stopBroadcast();

        // DEPLOY SHORTDN (LONG WUSDN)
        DeployShortdnFork deployShortdnFork = new DeployShortdnFork();
        deployShortdnFork.run();
    }
}

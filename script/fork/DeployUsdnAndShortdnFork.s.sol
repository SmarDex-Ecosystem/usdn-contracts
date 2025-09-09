// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { Script } from "forge-std/Script.sol";

import { Sdex } from "../../test/utils/Sdex.sol";

import { DeployShortdnFork } from "./DeployShortdnFork.s.sol";
import { DeployUsdnFork } from "./DeployUsdnFork.s.sol";

import { LiquidationRewardsManagerWstEth } from
    "../../src/LiquidationRewardsManager/LiquidationRewardsManagerWstEth.sol";
import { LiquidationRewardsManagerWusdn } from "../../src/LiquidationRewardsManager/LiquidationRewardsManagerWusdn.sol";
import { WstEthOracleMiddlewareWithPyth } from "../../src/OracleMiddleware/WstEthOracleMiddlewareWithPyth.sol";
import { WusdnToEthOracleMiddlewareWithPyth } from "../../src/OracleMiddleware/WusdnToEthOracleMiddlewareWithPyth.sol";
import { Rebalancer } from "../../src/Rebalancer/Rebalancer.sol";
import { Usdn } from "../../src/Usdn/Usdn.sol";
import { UsdnNoRebase } from "../../src/Usdn/UsdnNoRebase.sol";
import { IWstETH } from "../../src/interfaces/IWstETH.sol";
import { IWusdn } from "../../src/interfaces/Usdn/IWusdn.sol";
import { IUsdnProtocol } from "../../src/interfaces/UsdnProtocol/IUsdnProtocol.sol";

struct DeployedUsdnAndShortdn {
    // SDEX
    Sdex sdex;
    // USDN START
    IWstETH wsteth;
    WstEthOracleMiddlewareWithPyth wstEthOracleMiddleware;
    LiquidationRewardsManagerWstEth liquidationRewardsManagerWstEth;
    Rebalancer rebalancerusdn;
    Usdn usdn;
    IWusdn wusdn;
    IUsdnProtocol usdnProtocolusdn;
    // SHORTDN START
    WusdnToEthOracleMiddlewareWithPyth wusdnToEthOracleMiddleware;
    LiquidationRewardsManagerWusdn liquidationRewardsManagerWusdn;
    Rebalancer rebalancerShortdn;
    UsdnNoRebase usdnNoRebaseShortdn;
    IUsdnProtocol usdnProtocolShortdn;
}

contract DeployUsdnAndShortdnFork is Script {
    /**
     * @notice Deploy the USDN ecosystem with the WstETH as underlying and the SHORTDN ecosystem with the WUSDN as
     * underlying
     */
    function run() external returns (DeployedUsdnAndShortdn memory deployedUsdnAndShortdn) {
        // Deploy USDN (LONG ETH)
        DeployUsdnFork deployUsdnFork = new DeployUsdnFork();

        // Get values from runAndReturnValues and assign them step by step to avoid stack too deep
        {
            (
                WstEthOracleMiddlewareWithPyth wstEthOracleMiddleware,
                LiquidationRewardsManagerWstEth liquidationRewardsManager,
                Rebalancer rebalancer,
                Usdn usdn,
                IWusdn wusdn,
                IUsdnProtocol usdnProtocol
            ) = deployUsdnFork.run();

            // Assign to struct
            deployedUsdnAndShortdn.sdex = Sdex(address(usdnProtocol.getSdex()));
            deployedUsdnAndShortdn.wsteth = IWstETH(address(usdnProtocol.getAsset()));
            deployedUsdnAndShortdn.wstEthOracleMiddleware = wstEthOracleMiddleware;
            deployedUsdnAndShortdn.liquidationRewardsManagerWstEth = liquidationRewardsManager;
            deployedUsdnAndShortdn.rebalancerusdn = rebalancer;
            deployedUsdnAndShortdn.usdn = usdn;
            deployedUsdnAndShortdn.wusdn = wusdn;
            deployedUsdnAndShortdn.usdnProtocolusdn = usdnProtocol;
        }

        // Define future SHORTDN collateral aka WUSDN of already deployed USDN protocol
        vm.setEnv("UNDERLYING_ADDRESS_WUSDN", vm.toString(address(deployedUsdnAndShortdn.wusdn)));

        // Wrap USDN into WUSDN and approve it to the SHORTDN protocol
        vm.startBroadcast(msg.sender);
        deployedUsdnAndShortdn.usdn.approve(address(deployedUsdnAndShortdn.wusdn), type(uint256).max);
        deployedUsdnAndShortdn.wusdn.wrap(deployedUsdnAndShortdn.usdn.balanceOf(msg.sender));
        deployedUsdnAndShortdn.wusdn.approve(address(deployedUsdnAndShortdn.usdnProtocolusdn), type(uint256).max);
        vm.stopBroadcast();

        // Deploy SHORTDN (LONG WUSDN)
        DeployShortdnFork deployShortdnFork = new DeployShortdnFork();
        (
            deployedUsdnAndShortdn.wusdnToEthOracleMiddleware,
            deployedUsdnAndShortdn.liquidationRewardsManagerWusdn,
            deployedUsdnAndShortdn.rebalancerShortdn,
            deployedUsdnAndShortdn.usdnNoRebaseShortdn,
            deployedUsdnAndShortdn.usdnProtocolShortdn
        ) = deployShortdnFork.run();
    }
}

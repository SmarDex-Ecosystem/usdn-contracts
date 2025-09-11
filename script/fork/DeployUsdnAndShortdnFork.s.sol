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
     * @notice Deploy the USDN ecosystem with WstETH as underlying and the SHORTDN ecosystem with WUSDN as underlying
     * @return deployedUsdnAndShortdn_ The deployed USDN and SHORTDN contracts structure
     */
    function run() external returns (DeployedUsdnAndShortdn memory deployedUsdnAndShortdn_) {
        // Deploy USDN (LONG ETH)
        DeployUsdnFork deployUsdnFork = new DeployUsdnFork();

        // Get values from run into a struct to avoid stack too deep
        {
            (
                deployedUsdnAndShortdn_.wstEthOracleMiddleware,
                deployedUsdnAndShortdn_.liquidationRewardsManagerWstEth,
                deployedUsdnAndShortdn_.rebalancerusdn,
                deployedUsdnAndShortdn_.usdn,
                deployedUsdnAndShortdn_.wusdn,
                deployedUsdnAndShortdn_.usdnProtocolusdn
            ) = deployUsdnFork.run();

            // Assign to struct
            deployedUsdnAndShortdn_.sdex = Sdex(address(deployedUsdnAndShortdn_.usdnProtocolusdn.getSdex()));
            deployedUsdnAndShortdn_.wsteth = IWstETH(address(deployedUsdnAndShortdn_.usdnProtocolusdn.getAsset()));
        }

        // Define future SHORTDN collateral aka WUSDN of already deployed USDN protocol
        vm.setEnv("UNDERLYING_ADDRESS_WUSDN", vm.toString(address(deployedUsdnAndShortdn_.wusdn)));

        // Wrap USDN into WUSDN and approve it to the SHORTDN protocol
        vm.startBroadcast(msg.sender);
        deployedUsdnAndShortdn_.usdn.approve(address(deployedUsdnAndShortdn_.wusdn), type(uint256).max);
        deployedUsdnAndShortdn_.wusdn.wrap(deployedUsdnAndShortdn_.usdn.balanceOf(msg.sender));
        deployedUsdnAndShortdn_.wusdn.approve(address(deployedUsdnAndShortdn_.usdnProtocolusdn), type(uint256).max);
        vm.stopBroadcast();

        // Deploy SHORTDN (LONG WUSDN)
        DeployShortdnFork deployShortdnFork = new DeployShortdnFork();
        (
            deployedUsdnAndShortdn_.wusdnToEthOracleMiddleware,
            deployedUsdnAndShortdn_.liquidationRewardsManagerWusdn,
            deployedUsdnAndShortdn_.rebalancerShortdn,
            deployedUsdnAndShortdn_.usdnNoRebaseShortdn,
            deployedUsdnAndShortdn_.usdnProtocolShortdn
        ) = deployShortdnFork.run();
    }
}

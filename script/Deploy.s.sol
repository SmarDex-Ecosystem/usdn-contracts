// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { Script } from "forge-std/Script.sol";

import { WstETH } from "test/utils/WstEth.sol";
import { MockChainlinkOnChain } from "test/unit/OracleMiddleware/utils/MockChainlinkOnChain.sol";

import { IOracleMiddleware } from "src/interfaces/OracleMiddleware/IOracleMiddleware.sol";
import { LiquidationRewardsManager } from "src/OracleMiddleware/LiquidationRewardsManager.sol";
import { IWstETH } from "src/interfaces/IWstETH.sol";
import { Usdn } from "src/Usdn.sol";
import { UsdnProtocol } from "src/UsdnProtocol/UsdnProtocol.sol";
import { WstEthOracleMiddleware } from "src/OracleMiddleware/WstEthOracleMiddleware.sol";
import { MockWstEthOracleMiddleware } from "src/OracleMiddleware/mock/MockWstEthOracleMiddleware.sol";

contract Deploy is Script {
    function run() external {
        vm.startBroadcast(vm.envAddress("DEPLOYER_ADDRESS"));

        uint256 depositAmount = vm.envOr("INIT_DEPOSIT_AMOUNT", uint256(0));
        uint256 longAmount = vm.envOr("INIT_LONG_AMOUNT", uint256(0));

        // Deploy wstETH if needed
        address payable wstETHAddress = payable(vm.envOr("WSTETH_ADDRESS", address(0)));
        WstETH wstETH;
        if (wstETHAddress != address(0)) {
            wstETH = WstETH(wstETHAddress);
            if (vm.envOr("GET_WSTETH", false) && depositAmount > 0 && longAmount > 0) {
                uint256 ethAmount = (depositAmount + longAmount + 1000) * wstETH.stEthPerToken() / 1 ether;
                (bool result,) = wstETHAddress.call{ value: ethAmount }(hex"");
                require(result, "Failed to mint wstETH");
            }
        } else {
            wstETH = new WstETH();
            wstETHAddress = payable(address(wstETH));
        }

        // Deploy oracle middleware if needed
        // fetch middleware address environment variable
        address middlewareAddress = vm.envOr("MIDDLEWARE_ADDRESS", address(0));
        // cache environment type
        bool isProdEnv = block.chainid != 31_337;
        // cache middleware
        WstEthOracleMiddleware middleware;

        // attach
        if (middlewareAddress != address(0)) {
            // prod
            if (isProdEnv) {
                middleware = WstEthOracleMiddleware(middlewareAddress);
                // fork
            } else {
                middleware = MockWstEthOracleMiddleware(middlewareAddress);
            }

            // deploy
        } else {
            address pythAddress = vm.envAddress("PYTH_ADDRESS");
            bytes32 pythPriceId = vm.envBytes32("PYTH_STETH_PRICE_ID");
            address chainlinkPriceAddress = vm.envAddress("CHAINLINK_STETH_PRICE_ADDRESS");

            // prod
            if (isProdEnv) {
                middleware = new WstEthOracleMiddleware(
                    pythAddress, pythPriceId, chainlinkPriceAddress, wstETHAddress, (1 hours + 2 minutes)
                );
                // fork
            } else {
                middleware = new MockWstEthOracleMiddleware(
                    pythAddress, pythPriceId, chainlinkPriceAddress, wstETHAddress, 1 hours
                );
            }

            middlewareAddress = address(middleware);
        }

        // Deploy the LiquidationRewardsManager if necessary
        address liquidationRewardsManagerAddress = vm.envOr("LIQUIDATION_REWARDS_MANAGER_ADDRESS", address(0));
        LiquidationRewardsManager liquidationRewardsManager;
        if (liquidationRewardsManagerAddress != address(0)) {
            liquidationRewardsManager = LiquidationRewardsManager(liquidationRewardsManagerAddress);
        } else {
            address chainlinkGasPriceFeed = vm.envAddress("CHAINLINK_GAS_PRICE_ADDRESS");
            if (!isProdEnv) {
                chainlinkGasPriceFeed = address(new MockChainlinkOnChain());
            }

            // Heartbeat is 2 hours but I've seen the aggregator takes a bit more time to process the update TX.
            liquidationRewardsManager =
                new LiquidationRewardsManager(chainlinkGasPriceFeed, IWstETH(wstETHAddress), (2 hours + 10 minutes));
        }

        // Deploy USDN token, without a specific minter or adjuster for now
        address usdnAddress = vm.envOr("USDN_ADDRESS", address(0));
        Usdn usdn;
        if (usdnAddress != address(0)) {
            usdn = Usdn(usdnAddress);
        } else {
            usdn = new Usdn(address(0), address(0));
            usdnAddress = address(usdn);
        }

        // Deploy the protocol with tick spacing 100 = 1%
        UsdnProtocol protocol = new UsdnProtocol(usdn, wstETH, middleware, liquidationRewardsManager, 100);

        // Grant USDN minter role to protocol and approve wstETH spending

        usdn.grantRole(usdn.MINTER_ROLE(), address(protocol));
        wstETH.approve(address(protocol), depositAmount + longAmount);
        // Initialize if needed
        if (depositAmount > 0 && longAmount > 0) {
            // Desired liquidation price at 1 USD
            protocol.initialize(uint128(depositAmount), uint128(longAmount), 1 ether, "");
        }

        vm.stopBroadcast();
    }
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { Script } from "forge-std/Script.sol";

import { Sdex } from "test/utils/Sdex.sol";
import { WstETH } from "test/utils/WstEth.sol";

import { LiquidationRewardsManager } from "src/OracleMiddleware/LiquidationRewardsManager.sol";
import { IWstETH } from "src/interfaces/IWstETH.sol";
import { OrderManager } from "src/OrderManager.sol";
import { Usdn } from "src/Usdn.sol";
import { UsdnProtocol } from "src/UsdnProtocol/UsdnProtocol.sol";
import { ProtocolAction } from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import { WstEthOracleMiddleware } from "src/OracleMiddleware/WstEthOracleMiddleware.sol";
import { MockWstEthOracleMiddleware } from "src/OracleMiddleware/mock/MockWstEthOracleMiddleware.sol";
import { MockLiquidationRewardsManager } from "src/OracleMiddleware/mock/MockLiquidationRewardsManager.sol";

contract Deploy is Script {
    function run()
        external
        returns (
            WstETH WstETH_,
            Sdex Sdex_,
            WstEthOracleMiddleware WstEthOracleMiddleware_,
            LiquidationRewardsManager LiquidationRewardsManager_,
            OrderManager OrderManager_,
            Usdn Usdn_,
            UsdnProtocol UsdnProtocol_
        )
    {
        vm.startBroadcast(vm.envAddress("DEPLOYER_ADDRESS"));

        uint256 depositAmount = vm.envOr("INIT_DEPOSIT_AMOUNT", uint256(0));
        uint256 longAmount = vm.envOr("INIT_LONG_AMOUNT", uint256(0));

        // Deploy wstETH if needed
        address payable wstETHAddress = payable(vm.envOr("WSTETH_ADDRESS", address(0)));
        if (wstETHAddress != address(0)) {
            WstETH_ = WstETH(wstETHAddress);
            if (vm.envOr("GET_WSTETH", false) && depositAmount > 0 && longAmount > 0) {
                uint256 ethAmount = (depositAmount + longAmount + 10_000) * WstETH_.stEthPerToken() / 1 ether;
                (bool result,) = wstETHAddress.call{ value: ethAmount }(hex"");
                require(result, "Failed to mint wstETH");
            }
        } else {
            WstETH_ = new WstETH();
            wstETHAddress = payable(address(WstETH_));
        }

        // Deploy SDEX if needed
        address sdexAddress = payable(vm.envOr("SDEX_ADDRESS", address(0)));
        if (sdexAddress != address(0)) {
            Sdex_ = Sdex(sdexAddress);
        } else {
            Sdex_ = new Sdex();
            sdexAddress = address(Sdex_);
        }

        // Deploy oracle middleware if needed
        // fetch middleware address environment variable
        address middlewareAddress = vm.envOr("MIDDLEWARE_ADDRESS", address(0));
        // cache environment type
        bool isProdEnv = block.chainid != vm.envOr("FORK_CHAIN_ID", uint256(31_337));

        // attach
        if (middlewareAddress != address(0)) {
            // prod
            if (isProdEnv) {
                WstEthOracleMiddleware_ = WstEthOracleMiddleware(middlewareAddress);
                // fork
            } else {
                WstEthOracleMiddleware_ = MockWstEthOracleMiddleware(middlewareAddress);
            }

            // deploy
        } else {
            address pythAddress = vm.envAddress("PYTH_ADDRESS");
            bytes32 pythPriceId = vm.envBytes32("PYTH_STETH_PRICE_ID");
            address chainlinkPriceAddress = vm.envAddress("CHAINLINK_STETH_PRICE_ADDRESS");
            uint256 chainlinkPriceValidity = vm.envOr("CHAINLINK_STETH_PRICE_VALIDITY", uint256(1 hours + 2 minutes));

            // prod
            if (isProdEnv) {
                WstEthOracleMiddleware_ = new WstEthOracleMiddleware(
                    pythAddress, pythPriceId, chainlinkPriceAddress, wstETHAddress, chainlinkPriceValidity
                );
                // fork
            } else {
                WstEthOracleMiddleware_ = new MockWstEthOracleMiddleware(
                    pythAddress, pythPriceId, chainlinkPriceAddress, wstETHAddress, chainlinkPriceValidity
                );
            }

            middlewareAddress = address(WstEthOracleMiddleware_);
        }

        // Deploy the LiquidationRewardsManager if necessary
        address liquidationRewardsManagerAddress = vm.envOr("LIQUIDATION_REWARDS_MANAGER_ADDRESS", address(0));

        if (liquidationRewardsManagerAddress != address(0)) {
            if (isProdEnv) {
                LiquidationRewardsManager_ = LiquidationRewardsManager(liquidationRewardsManagerAddress);
            } else {
                LiquidationRewardsManager_ = MockLiquidationRewardsManager(liquidationRewardsManagerAddress);
            }
        } else {
            address chainlinkGasPriceFeed = vm.envAddress("CHAINLINK_GAS_PRICE_ADDRESS");
            uint256 chainlinkPriceValidity = vm.envOr("CHAINLINK_GAS_PRICE_VALIDITY", uint256(2 hours + 5 minutes));
            if (isProdEnv) {
                LiquidationRewardsManager_ =
                    new LiquidationRewardsManager(chainlinkGasPriceFeed, IWstETH(wstETHAddress), chainlinkPriceValidity);
            } else {
                LiquidationRewardsManager_ = new MockLiquidationRewardsManager(
                    chainlinkGasPriceFeed, IWstETH(wstETHAddress), chainlinkPriceValidity
                );
            }

            liquidationRewardsManagerAddress = address(LiquidationRewardsManager_);
        }

        // Deploy USDN token, without a specific minter or rebaser for now
        address usdnAddress = vm.envOr("USDN_ADDRESS", address(0));
        if (usdnAddress != address(0)) {
            Usdn_ = Usdn(usdnAddress);
        } else {
            Usdn_ = new Usdn(address(0), address(0));
            usdnAddress = address(Usdn_);
        }

        // Deploy the protocol with tick spacing 100 = 1%
        UsdnProtocol_ = new UsdnProtocol(
            Usdn_,
            Sdex_,
            WstETH_,
            WstEthOracleMiddleware_,
            LiquidationRewardsManager_,
            100,
            vm.envAddress("FEE_COLLECTOR")
        );

        // Deploy the OrderManager if necessary
        address orderManagerAddress = vm.envOr("ORDER_MANAGER_ADDRESS", address(0));
        if (orderManagerAddress != address(0)) {
            OrderManager_ = OrderManager(orderManagerAddress);
        } else {
            OrderManager_ = new OrderManager(UsdnProtocol_);
        }

        // Set the order manager on the USDN protocol
        UsdnProtocol_.setOrderManager(OrderManager_);

        // Grant USDN minter & rebaser roles to protocol and approve wstETH spending
        Usdn_.grantRole(Usdn_.MINTER_ROLE(), address(UsdnProtocol_));
        Usdn_.grantRole(Usdn_.REBASER_ROLE(), address(UsdnProtocol_));
        WstETH_.approve(address(UsdnProtocol_), depositAmount + longAmount);

        // Initialize if needed
        if (depositAmount > 0 && longAmount > 0) {
            uint256 desiredLiqPrice;
            if (isProdEnv) {
                desiredLiqPrice = vm.envUint("INIT_LONG_LIQPRICE");
            } else {
                // for forks, we want a leverage of ~2x so we get the current
                // price from the middleware and divide it by two
                desiredLiqPrice = WstEthOracleMiddleware_.parseAndValidatePrice(
                    uint128(block.timestamp), ProtocolAction.Initialize, ""
                ).price / 2;
            }
            UsdnProtocol_.initialize(uint128(depositAmount), uint128(longAmount), uint128(desiredLiqPrice), "");
        }

        vm.stopBroadcast();
    }
}

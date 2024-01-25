// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { Script } from "forge-std/Script.sol";

import { WstETH } from "test/utils/WstEth.sol";

import { IOracleMiddleware } from "src/interfaces/IOracleMiddleware.sol";
import { Usdn } from "src/Usdn.sol";
import { UsdnProtocol } from "src/UsdnProtocol/UsdnProtocol.sol";
import { OracleMiddleware } from "../src/OracleMiddleware/OracleMiddleware.sol";

contract Deploy is Script {
    function run() external {
        vm.startBroadcast(vm.envAddress("DEPLOYER_ADDRESS"));

        // Deploy wstETH if needed
        address payable wstETHAddress = payable(vm.envOr("WSTETH_ADDRESS", address(0)));
        WstETH wstETH;
        if (wstETHAddress != address(0)) {
            wstETH = WstETH(wstETHAddress);
        } else {
            wstETH = new WstETH();
            wstETHAddress = payable(address(wstETH));
        }

        // Deploy Oracle middleware if needed
        address middlewareAddress = vm.envOr("MIDDLEWARE_ADDRESS", address(0));
        IOracleMiddleware middleware;
        if (middlewareAddress != address(0)) {
            middleware = IOracleMiddleware(middlewareAddress);
        } else {
            address pythAddress = vm.envAddress("PYTH_ADDRESS");
            bytes32 pythPriceId = vm.envBytes32("PYTH_WSTETH_PRICE_ID");
            address chainlinkPriceAddress = vm.envAddress("CHAINLINK_STETH_PRICE_ADDRESS");
            middleware = new OracleMiddleware(pythAddress, pythPriceId, chainlinkPriceAddress);
            middlewareAddress = address(middleware);
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
        UsdnProtocol protocol = new UsdnProtocol(usdn, wstETH, middleware, 100);

        // Grant USDN minter role to protocol and approve wstETH spending
        uint256 depositAmount = vm.envOr("INIT_DEPOSIT_AMOUNT", uint256(0));
        uint256 longAmount = vm.envOr("INIT_LONG_AMOUNT", uint256(0));
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

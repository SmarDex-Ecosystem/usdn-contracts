// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { Script } from "forge-std/Script.sol";

import { WstETH } from "../test/utils/WstEth.sol";

import { WstEthOracleMiddlewareWithRedstone } from "../src/OracleMiddleware/WstEthOracleMiddlewareWithRedstone.sol";
import { MockWstEthOracleMiddlewareWithRedstone } from
    "../src/OracleMiddleware/mock/MockWstEthOracleMiddlewareWithRedstone.sol";

contract DeployRedstoneMiddleware is Script {
    function run() external returns (WstEthOracleMiddlewareWithRedstone WstEthOracleMiddlewareWithRedstone_) {
        bool isProdEnv = block.chainid != vm.envOr("FORK_CHAIN_ID", uint256(31_337));

        vm.startBroadcast(vm.envAddress("DEPLOYER_ADDRESS"));

        WstEthOracleMiddlewareWithRedstone_ = _deployWstEthOracleMiddleware(isProdEnv);

        vm.stopBroadcast();
    }

    /**
     * @notice Deploy the WstETH oracle middleware if necessary
     * @dev Will return the already deployed one if an address is in the env variables
     * @param isProdEnv Env check
     * @return wstEthOracleMiddleware_ The deployed contract
     */
    function _deployWstEthOracleMiddleware(bool isProdEnv)
        internal
        returns (WstEthOracleMiddlewareWithRedstone wstEthOracleMiddleware_)
    {
        address wstETHAddress = vm.envAddress("WSTETH_ADDRESS");

        address pythAddress = vm.envAddress("PYTH_ADDRESS");
        bytes32 pythFeedId = vm.envBytes32("PYTH_ETH_FEED_ID");
        bytes32 redstoneFeedId = vm.envBytes32("REDSTONE_ETH_FEED_ID");
        address chainlinkPriceAddress = vm.envAddress("CHAINLINK_ETH_PRICE_ADDRESS");
        uint256 chainlinkPriceValidity = vm.envOr("CHAINLINK_ETH_PRICE_VALIDITY", uint256(1 hours + 2 minutes));

        if (isProdEnv) {
            wstEthOracleMiddleware_ = new WstEthOracleMiddlewareWithRedstone(
                pythAddress, pythFeedId, redstoneFeedId, chainlinkPriceAddress, wstETHAddress, chainlinkPriceValidity
            );
        } else {
            wstEthOracleMiddleware_ = new MockWstEthOracleMiddlewareWithRedstone(
                pythAddress, pythFeedId, redstoneFeedId, chainlinkPriceAddress, wstETHAddress, chainlinkPriceValidity
            );
        }
    }
}

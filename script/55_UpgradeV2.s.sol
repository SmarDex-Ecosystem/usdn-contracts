// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { Script } from "forge-std/Script.sol";

import { UsdnWstethUsdConfig } from "./deploymentConfigs/UsdnWstethUsdConfig.sol";
import { Utils } from "./utils/Utils.s.sol";

import { UsdnProtocolFallback } from "../src/UsdnProtocol/UsdnProtocolFallback.sol";
import { UsdnProtocolImpl } from "../src/UsdnProtocol/UsdnProtocolImpl.sol";
import { UsdnProtocolConstantsLibrary as Constants } from
    "../src/UsdnProtocol/libraries/UsdnProtocolConstantsLibrary.sol";
import { IUsdnProtocol } from "../src/interfaces/UsdnProtocol/IUsdnProtocol.sol";

/**
 * @title Upgrade script
 * @notice This script is only made for upgrading the Usdn protocol from v1.x.x to v2.0.0.
 * @dev The sender must already have the `PROXY_UPGRADE_ROLE` before launching this script.
 */
contract UpgradeV2 is UsdnWstethUsdConfig, Script {
    IUsdnProtocol constant USDN_PROTOCOL = IUsdnProtocol(0x656cB8C6d154Aad29d8771384089be5B5141f01a);

    /// @dev this is the keccak-256 hash of "eip1967.proxy.implementation" subtracted by 1.
    bytes32 constant IMPL_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    Utils utils;

    constructor() {
        utils = new Utils();
    }

    function run()
        external
        returns (UsdnProtocolFallback newUsdnProtocolFallback_, UsdnProtocolImpl newUsdnProtocolImpl_)
    {
        utils.validateProtocol("UsdnProtocolImpl", "UsdnProtocolFallback");

        require(
            USDN_PROTOCOL.hasRole(Constants.PROXY_UPGRADE_ROLE, msg.sender),
            "Sender does not have the permission to upgrade the protocol"
        );
        bytes32 oldImpl = vm.load(address(USDN_PROTOCOL), IMPL_SLOT);

        vm.startBroadcast();

        newUsdnProtocolFallback_ = new UsdnProtocolFallback(MAX_SDEX_BURN_RATIO, MAX_MIN_LONG_POSITION);
        newUsdnProtocolImpl_ = new UsdnProtocolImpl();
        USDN_PROTOCOL.upgradeToAndCall(
            address(newUsdnProtocolImpl_),
            // abi.encodeWithSelector(UsdnProtocolImpl.initializeStorageV2.selector, address(newUsdnProtocolFallback_))
            abi.encodeWithSelector(UsdnProtocolImpl.initializeStorage.selector, address(newUsdnProtocolFallback_))
        );

        bytes32 newImpl = vm.load(address(USDN_PROTOCOL), IMPL_SLOT);
        require(oldImpl != newImpl, "Upgrade failed");
        require(address(uint160(uint256(newImpl))) == address(newUsdnProtocolImpl_), "Upgrade failed");
        require(USDN_PROTOCOL.getSdexBurnOnDepositRatio() > 0, "New storage not initialized");
        require(USDN_PROTOCOL.getFallbackAddress() == address(newUsdnProtocolFallback_), "New fallback not set");

        vm.stopBroadcast();
    }
}

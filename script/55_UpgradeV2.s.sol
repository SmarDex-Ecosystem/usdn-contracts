// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { Script } from "forge-std/Script.sol";

import { UsdnProtocolImpl } from "../src/UsdnProtocol/UsdnProtocolImpl.sol";
import { UsdnProtocolConstantsLibrary as Constants } from
    "../src/UsdnProtocol/libraries/UsdnProtocolConstantsLibrary.sol";
import { IUsdnProtocol } from "../src/interfaces/UsdnProtocol/IUsdnProtocol.sol";

/**
 * @title Upgrade script
 * @notice This script is only made for upgrading the Usdn protocol from v1.0.x to v2.0.0.
 * @dev The sender must already have the `PROXY_UPGRADE_ROLE` before launching this script.
 */
contract Upgrade is Script {
    IUsdnProtocol constant USDN_PROTOCOL = IUsdnProtocol(0x656cB8C6d154Aad29d8771384089be5B5141f01a);
    bytes32 ImplAddrLocation = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    function run() external returns (UsdnProtocolImpl newUsdnProtocolImpl_) {
        require(
            USDN_PROTOCOL.hasRole(Constants.PROXY_UPGRADE_ROLE, msg.sender),
            "Sender does not have the permission to upgrade the protocol"
        );
        bytes32 oldImpl = vm.load(address(USDN_PROTOCOL), ImplAddrLocation);

        vm.startBroadcast();

        newUsdnProtocolImpl_ = new UsdnProtocolImpl();
        USDN_PROTOCOL.upgradeToAndCall(
            address(newUsdnProtocolImpl_), abi.encodeWithSelector(UsdnProtocolImpl.initializeStorageV2.selector)
        );
        bytes32 newImpl = vm.load(address(USDN_PROTOCOL), ImplAddrLocation);
        require(oldImpl != newImpl, "Upgrade failed");
        require(address(uint160(uint256(newImpl))) == address(newUsdnProtocolImpl_), "Upgrade failed");

        vm.stopBroadcast();
    }
}

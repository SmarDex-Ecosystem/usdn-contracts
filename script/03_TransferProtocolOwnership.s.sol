// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { Script } from "forge-std/Script.sol";

import { IUsdnProtocol } from "../src/interfaces/UsdnProtocol/IUsdnProtocol.sol";

contract TransferProtocolOwnership is Script {
    function run() external {
        address newOwner = vm.envAddress("NEW_OWNER_ADDRESS");
        IUsdnProtocol protocol = IUsdnProtocol(vm.envAddress("PROTOCOL_ADDRESS"));
        address defaultAdmin = protocol.defaultAdmin();

        Roles memory roles = Roles({
            externalManagerRole: protocol.SET_EXTERNAL_ROLE(),
            criticalFunctionsRole: protocol.CRITICAL_FUNCTIONS_ROLE(),
            setProtocolParamsRole: protocol.SET_PROTOCOL_PARAMS_ROLE(),
            setUsdnParamsRole: protocol.SET_USDN_PARAMS_ROLE(),
            setOptionsRole: protocol.SET_OPTIONS_ROLE(),
            proxyUpgradeRole: protocol.PROXY_UPGRADE_ROLE(),
            pauserRole: protocol.PAUSER_ROLE(),
            unpauserRole: protocol.UNPAUSER_ROLE(),
            adminExternalManagerRole: protocol.ADMIN_SET_EXTERNAL_ROLE(),
            adminCriticalFunctionsRole: protocol.ADMIN_CRITICAL_FUNCTIONS_ROLE(),
            adminSetProtocolParamsRole: protocol.ADMIN_SET_PROTOCOL_PARAMS_ROLE(),
            adminSetUsdnParamsRole: protocol.ADMIN_SET_USDN_PARAMS_ROLE(),
            adminSetOptionsRole: protocol.ADMIN_SET_OPTIONS_ROLE(),
            adminProxyUpgradeRole: protocol.ADMIN_PROXY_UPGRADE_ROLE(),
            adminPauserRole: protocol.ADMIN_PAUSER_ROLE(),
            adminUnpauserRole: protocol.ADMIN_UNPAUSER_ROLE()
        });

        vm.startBroadcast(defaultAdmin);

        // transfer roles
        protocol.grantRole(roles.externalManagerRole, newOwner);
        protocol.grantRole(roles.criticalFunctionsRole, newOwner);
        protocol.grantRole(roles.setProtocolParamsRole, newOwner);
        protocol.grantRole(roles.setUsdnParamsRole, newOwner);
        protocol.grantRole(roles.setOptionsRole, newOwner);
        protocol.grantRole(roles.proxyUpgradeRole, newOwner);
        protocol.grantRole(roles.pauserRole, newOwner);
        protocol.grantRole(roles.unpauserRole, newOwner);

        // transfer admin roles
        protocol.grantRole(roles.adminExternalManagerRole, newOwner);
        protocol.grantRole(roles.adminCriticalFunctionsRole, newOwner);
        protocol.grantRole(roles.adminSetProtocolParamsRole, newOwner);
        protocol.grantRole(roles.adminSetUsdnParamsRole, newOwner);
        protocol.grantRole(roles.adminSetOptionsRole, newOwner);
        protocol.grantRole(roles.adminProxyUpgradeRole, newOwner);
        protocol.grantRole(roles.adminPauserRole, newOwner);
        protocol.grantRole(roles.adminUnpauserRole, newOwner);

        // transfer default admin
        protocol.beginDefaultAdminTransfer(newOwner);

        vm.stopBroadcast();
    }

    struct Roles {
        bytes32 externalManagerRole;
        bytes32 criticalFunctionsRole;
        bytes32 setProtocolParamsRole;
        bytes32 setUsdnParamsRole;
        bytes32 setOptionsRole;
        bytes32 proxyUpgradeRole;
        bytes32 pauserRole;
        bytes32 unpauserRole;
        bytes32 adminExternalManagerRole;
        bytes32 adminCriticalFunctionsRole;
        bytes32 adminSetProtocolParamsRole;
        bytes32 adminSetUsdnParamsRole;
        bytes32 adminSetOptionsRole;
        bytes32 adminProxyUpgradeRole;
        bytes32 adminPauserRole;
        bytes32 adminUnpauserRole;
    }
}

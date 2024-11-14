// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { BaseFixture } from "./Fixtures.sol";

import "./Constants.sol" as constants;

import { UsdnProtocolConstantsLibrary as Constants } from
    "../../src/UsdnProtocol/libraries/UsdnProtocolConstantsLibrary.sol";
import { IUsdnProtocol } from "../../src/interfaces/UsdnProtocol/IUsdnProtocol.sol";

contract RolesUtils is BaseFixture {
    function _giveRolesTo(Managers memory managers, IUsdnProtocol usdnProtocol) internal {
        address defaultAdmin = usdnProtocol.defaultAdmin();
        vm.startPrank(defaultAdmin);
        usdnProtocol.grantRole(Constants.ADMIN_CRITICAL_FUNCTIONS_ROLE, constants.ADMIN);
        usdnProtocol.grantRole(Constants.ADMIN_SET_EXTERNAL_ROLE, constants.ADMIN);
        usdnProtocol.grantRole(Constants.ADMIN_SET_PROTOCOL_PARAMS_ROLE, constants.ADMIN);
        usdnProtocol.grantRole(Constants.ADMIN_SET_USDN_PARAMS_ROLE, constants.ADMIN);
        usdnProtocol.grantRole(Constants.ADMIN_SET_OPTIONS_ROLE, constants.ADMIN);
        usdnProtocol.grantRole(Constants.ADMIN_PROXY_UPGRADE_ROLE, constants.ADMIN);
        usdnProtocol.grantRole(Constants.ADMIN_PAUSER_ROLE, constants.ADMIN);
        usdnProtocol.grantRole(Constants.ADMIN_UNPAUSER_ROLE, constants.ADMIN);
        vm.stopPrank();

        vm.startPrank(constants.ADMIN);
        usdnProtocol.grantRole(Constants.CRITICAL_FUNCTIONS_ROLE, managers.criticalFunctionsManager);
        usdnProtocol.grantRole(Constants.SET_EXTERNAL_ROLE, managers.setExternalManager);
        usdnProtocol.grantRole(Constants.SET_PROTOCOL_PARAMS_ROLE, managers.setProtocolParamsManager);
        usdnProtocol.grantRole(Constants.SET_USDN_PARAMS_ROLE, managers.setUsdnParamsManager);
        usdnProtocol.grantRole(Constants.SET_OPTIONS_ROLE, managers.setOptionsManager);
        usdnProtocol.grantRole(Constants.PROXY_UPGRADE_ROLE, managers.proxyUpgradeManager);
        usdnProtocol.grantRole(Constants.PAUSER_ROLE, managers.pauserManager);
        usdnProtocol.grantRole(Constants.UNPAUSER_ROLE, managers.unpauserManager);
        vm.stopPrank();
    }
}

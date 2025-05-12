// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import { UUPSUpgradeable } from "solady/src/utils/UUPSUpgradeable.sol";

import { IUsdnProtocolImpl } from "../interfaces/UsdnProtocol/IUsdnProtocolImpl.sol";
import { UsdnProtocolActions } from "./UsdnProtocolActions.sol";
import { UsdnProtocolCore } from "./UsdnProtocolCore.sol";
import { UsdnProtocolLong } from "./UsdnProtocolLong.sol";
import { UsdnProtocolVault } from "./UsdnProtocolVault.sol";
import { UsdnProtocolConstantsLibrary as Constants } from "./libraries/UsdnProtocolConstantsLibrary.sol";
import { UsdnProtocolSettersLibrary as Setters } from "./libraries/UsdnProtocolSettersLibrary.sol";
import { UsdnProtocolUtilsLibrary as Utils } from "./libraries/UsdnProtocolUtilsLibrary.sol";

contract UsdnProtocolImpl is
    IUsdnProtocolImpl,
    UsdnProtocolActions,
    UsdnProtocolCore,
    UsdnProtocolVault,
    UsdnProtocolLong,
    UUPSUpgradeable
{
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @inheritdoc IUsdnProtocolImpl
    function initializeStorage(InitStorage calldata initStorage) public reinitializer(2) {
        __AccessControlDefaultAdminRules_init(0, msg.sender);
        __initializeReentrancyGuard_init();
        __Pausable_init();
        __EIP712_init("UsdnProtocol", "1");

        _setRoleAdmin(Constants.SET_EXTERNAL_ROLE, Constants.ADMIN_SET_EXTERNAL_ROLE);
        _setRoleAdmin(Constants.CRITICAL_FUNCTIONS_ROLE, Constants.ADMIN_CRITICAL_FUNCTIONS_ROLE);
        _setRoleAdmin(Constants.SET_PROTOCOL_PARAMS_ROLE, Constants.ADMIN_SET_PROTOCOL_PARAMS_ROLE);
        _setRoleAdmin(Constants.SET_USDN_PARAMS_ROLE, Constants.ADMIN_SET_USDN_PARAMS_ROLE);
        _setRoleAdmin(Constants.SET_OPTIONS_ROLE, Constants.ADMIN_SET_OPTIONS_ROLE);
        _setRoleAdmin(Constants.PROXY_UPGRADE_ROLE, Constants.ADMIN_PROXY_UPGRADE_ROLE);
        _setRoleAdmin(Constants.PAUSER_ROLE, Constants.ADMIN_PAUSER_ROLE);
        _setRoleAdmin(Constants.UNPAUSER_ROLE, Constants.ADMIN_UNPAUSER_ROLE);

        Setters.setInitialStorage(initStorage);
    }

    /**
     * @inheritdoc UUPSUpgradeable
     * @notice Verifies that the caller is allowed to upgrade the protocol.
     * @param implementation The address of the new implementation contract.
     */
    function _authorizeUpgrade(address implementation) internal override onlyRole(Constants.PROXY_UPGRADE_ROLE) { }

    /**
     * @notice Delegates the call to the fallback contract.
     * @param protocolFallbackAddr The address of the fallback contract.
     */
    function _delegate(address protocolFallbackAddr) internal {
        assembly {
            calldatacopy(0, 0, calldatasize())
            let result := delegatecall(gas(), protocolFallbackAddr, 0, calldatasize(), 0, 0)
            returndatacopy(0, 0, returndatasize())
            switch result
            case 0 { revert(0, returndatasize()) }
            default { return(0, returndatasize()) }
        }
    }

    /**
     * @notice Delegates the call to the fallback contract if the function signature contained in the transaction data
     * does not match any function in the implementation contract.
     */
    fallback() external {
        _delegate(Utils._getMainStorage()._protocolFallbackAddr);
    }
}

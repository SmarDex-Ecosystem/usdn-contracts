// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import { AccessControlDefaultAdminRulesUpgradeable } from
    "@openzeppelin/contracts-upgradeable/access/extensions/AccessControlDefaultAdminRulesUpgradeable.sol";

import { IUsdnProtocolErrors } from "../interfaces/UsdnProtocol/IUsdnProtocolErrors.sol";
import { IUsdnProtocolStorage } from "../interfaces/UsdnProtocol/IUsdnProtocolStorage.sol";
import { InitializableReentrancyGuard } from "../utils/InitializableReentrancyGuard.sol";

abstract contract UsdnProtocolStorage is
    IUsdnProtocolErrors,
    IUsdnProtocolStorage,
    InitializableReentrancyGuard,
    AccessControlDefaultAdminRulesUpgradeable
{
    /// @notice The storage structure of the Usdn protocol
    Storage internal s;

    /// @inheritdoc IUsdnProtocolStorage
    bytes32 public constant SET_EXTERNAL_ROLE = keccak256("SET_EXTERNAL_ROLE");

    /// @inheritdoc IUsdnProtocolStorage
    bytes32 public constant CRITICAL_FUNCTIONS_ROLE = keccak256("CRITICAL_FUNCTIONS_ROLE");

    /// @inheritdoc IUsdnProtocolStorage
    bytes32 public constant SET_PROTOCOL_PARAMS_ROLE = keccak256("SET_PROTOCOL_PARAMS_ROLE");

    /// @inheritdoc IUsdnProtocolStorage
    bytes32 public constant SET_USDN_PARAMS_ROLE = keccak256("SET_USDN_PARAMS_ROLE");

    /// @inheritdoc IUsdnProtocolStorage
    bytes32 public constant SET_OPTIONS_ROLE = keccak256("SET_OPTIONS_ROLE");

    /// @inheritdoc IUsdnProtocolStorage
    bytes32 public constant PROXY_UPGRADE_ROLE = keccak256("PROXY_UPGRADE_ROLE");

    /// @inheritdoc IUsdnProtocolStorage
    bytes32 public constant ADMIN_SET_EXTERNAL_ROLE = keccak256("ADMIN_SET_EXTERNAL_ROLE");

    /// @inheritdoc IUsdnProtocolStorage
    bytes32 public constant ADMIN_CRITICAL_FUNCTIONS_ROLE = keccak256("ADMIN_CRITICAL_FUNCTIONS_ROLE");

    /// @inheritdoc IUsdnProtocolStorage
    bytes32 public constant ADMIN_SET_PROTOCOL_PARAMS_ROLE = keccak256("ADMIN_SET_PROTOCOL_PARAMS_ROLE");

    /// @inheritdoc IUsdnProtocolStorage
    bytes32 public constant ADMIN_SET_USDN_PARAMS_ROLE = keccak256("ADMIN_SET_USDN_PARAMS_ROLE");

    /// @inheritdoc IUsdnProtocolStorage
    bytes32 public constant ADMIN_SET_OPTIONS_ROLE = keccak256("ADMIN_SET_OPTIONS_ROLE");

    /// @inheritdoc IUsdnProtocolStorage
    bytes32 public constant ADMIN_PROXY_UPGRADE_ROLE = keccak256("ADMIN_PROXY_UPGRADE_ROLE");
}

// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import { IAccessControlDefaultAdminRules } from
    "@openzeppelin/contracts/access/extensions/IAccessControlDefaultAdminRules.sol";
import { IERC5267 } from "@openzeppelin/contracts/interfaces/IERC5267.sol";
import { IERC5313 } from "@openzeppelin/contracts/interfaces/IERC5313.sol";

import { IUsdnProtocolErrors } from "./IUsdnProtocolErrors.sol";
import { IUsdnProtocolEvents } from "./IUsdnProtocolEvents.sol";

/**
 * @title IUsdnProtocolStorage
 * @notice Interface for the storage layer of the USDN protocol
 */
interface IUsdnProtocolStorage is
    IUsdnProtocolEvents,
    IUsdnProtocolErrors,
    IAccessControlDefaultAdminRules,
    IERC5313,
    IERC5267
{
    /* -------------------------------------------------------------------------- */
    /*                                  Constants                                 */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice The setExternal role's signature
     * @dev This role is used to set the external contracts
     * @return Get the role signature
     */
    function SET_EXTERNAL_ROLE() external pure returns (bytes32);

    /**
     * @notice The criticalFunctions role's signature
     * @dev This role is used to perform critical functions
     * @return Get the role signature
     */
    function CRITICAL_FUNCTIONS_ROLE() external pure returns (bytes32);

    /**
     * @notice The setProtocolParams role's signature
     * @dev This role is used to set the protocol parameters
     * @return Get the role signature
     */
    function SET_PROTOCOL_PARAMS_ROLE() external pure returns (bytes32);

    /**
     * @notice The setOptions role's signature
     * @dev This role is used to set the protocol options that do not impact the usage of the protocol
     * @return Get the role signature
     */
    function SET_OPTIONS_ROLE() external pure returns (bytes32);

    /**
     * @notice The setUsdnParams role's signature
     * @dev This role is used to set the USDN parameters
     * @return Get the role signature
     */
    function SET_USDN_PARAMS_ROLE() external pure returns (bytes32);

    /**
     * @notice The proxyUpgrade role's signature
     * @dev This role is used to upgrade the protocol implementation
     * @return Get the role signature
     */
    function PROXY_UPGRADE_ROLE() external pure returns (bytes32);

    /**
     * @notice The pauser role's signature
     * @dev This role is used to pause the protocol
     * @return Get the role signature
     */
    function PAUSER_ROLE() external pure returns (bytes32);

    /**
     * @notice The unpauser role's signature
     * @dev This role is used to unpause the protocol
     * @return Get the role signature
     */
    function UNPAUSER_ROLE() external pure returns (bytes32);

    /**
     * @notice The adminSetExternal role's signature
     * @dev This role is used to revoke and grant the setExternal role
     * @return Get the role signature
     */
    function ADMIN_SET_EXTERNAL_ROLE() external pure returns (bytes32);

    /**
     * @notice The adminCriticalFunctions role's signature
     * @dev This role is used to revoke and grant the criticalFunctions role
     * @return Get the role signature
     */
    function ADMIN_CRITICAL_FUNCTIONS_ROLE() external pure returns (bytes32);

    /**
     * @notice The adminSetProtocolParams role's signature
     * @dev This role is used to revoke and grant the setProtocolParams role
     * @return Get the role signature
     */
    function ADMIN_SET_PROTOCOL_PARAMS_ROLE() external pure returns (bytes32);

    /**
     * @notice The adminSetUsdnParams role's signature
     * @dev This role is used to revoke and grant the setUsdnParams role
     * @return Get the role signature
     */
    function ADMIN_SET_USDN_PARAMS_ROLE() external pure returns (bytes32);

    /**
     * @notice The adminSetOptions role's signature
     * @dev This role is used to revoke and grant the setOptions role
     * @return Get the role signature
     */
    function ADMIN_SET_OPTIONS_ROLE() external pure returns (bytes32);

    /**
     * @notice The adminProxyUpgrade role's signature
     * @dev This role is used to revoke and grant the proxyUpgrade role
     * @return Get the role signature
     */
    function ADMIN_PROXY_UPGRADE_ROLE() external pure returns (bytes32);

    /**
     * @notice The adminPauser role's signature
     * @dev This role is used to revoke and grant the pauser role
     * @return Get the role signature
     */
    function ADMIN_PAUSER_ROLE() external pure returns (bytes32);

    /**
     * @notice The adminUnpauser role's signature
     * @dev This role is used to revoke and grant the unpauser role
     * @return Get the role signature
     */
    function ADMIN_UNPAUSER_ROLE() external pure returns (bytes32);
}

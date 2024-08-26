// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import { IAccessControlDefaultAdminRules } from
    "@openzeppelin/contracts/access/extensions/IAccessControlDefaultAdminRules.sol";
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
    IERC5313
{
    /* -------------------------------------------------------------------------- */
    /*                                  Constants                                 */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice The setExternal role's signature
     * @return Get the role signature
     */
    function SET_EXTERNAL_ROLE() external pure returns (bytes32);

    /**
     * @notice The criticalFunctions role's signature
     * @return Get the role signature
     */
    function CRITICAL_FUNCTIONS_ROLE() external pure returns (bytes32);

    /**
     * @notice The setProtocolParams role's signature
     * @return Get the role signature
     */
    function SET_PROTOCOL_PARAMS_ROLE() external pure returns (bytes32);

    /**
     * @notice The setOptions role's signature
     * @return Get the role signature
     */
    function SET_OPTIONS_ROLE() external pure returns (bytes32);

    /**
     * @notice The adminSetExternal role's signature
     * @return Get the role signature
     */
    function SET_USDN_PARAMS_ROLE() external pure returns (bytes32);

    /**
     * @notice The adminSetExternal role's signature
     * @return Get the role signature
     */
    function ADMIN_SET_EXTERNAL_ROLE() external pure returns (bytes32);

    /**
     * @notice The adminCriticalFunctions role's signature
     * @return Get the role signature
     */
    function ADMIN_CRITICAL_FUNCTIONS_ROLE() external pure returns (bytes32);

    /**
     * @notice The adminSetProtocolParams role's signature
     * @return Get the role signature
     */
    function ADMIN_SET_PROTOCOL_PARAMS_ROLE() external pure returns (bytes32);

    /**
     * @notice The adminSetUsdnParams role's signature
     * @return Get the role signature
     */
    function ADMIN_SET_USDN_PARAMS_ROLE() external pure returns (bytes32);

    /**
     * @notice The adminSetOptions role's signature
     * @return Get the role signature
     */
    function ADMIN_SET_OPTIONS_ROLE() external pure returns (bytes32);
}

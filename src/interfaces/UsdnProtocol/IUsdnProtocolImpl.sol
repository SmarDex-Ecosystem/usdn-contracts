// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import { IAccessControlDefaultAdminRules } from
    "@openzeppelin/contracts/access/extensions/IAccessControlDefaultAdminRules.sol";
import { IERC5267 } from "@openzeppelin/contracts/interfaces/IERC5267.sol";

import { IUsdnProtocolActions } from "./IUsdnProtocolActions.sol";
import { IUsdnProtocolCore } from "./IUsdnProtocolCore.sol";
import { IUsdnProtocolFallback } from "./IUsdnProtocolFallback.sol";
import { IUsdnProtocolLong } from "./IUsdnProtocolLong.sol";
import { IUsdnProtocolVault } from "./IUsdnProtocolVault.sol";

/**
 * @title IUsdnProtocolImpl
 * @notice Interface for the implementation of the USDN protocol (completed with {IUsdnProtocolFallback})
 */
interface IUsdnProtocolImpl is
    IUsdnProtocolActions,
    IUsdnProtocolVault,
    IUsdnProtocolLong,
    IUsdnProtocolCore,
    IAccessControlDefaultAdminRules,
    IERC5267
{
    /**
     * @notice Initializes the protocol's storage with the given values.
     * @dev This function should be called on deployment when creating the proxy.
     * It can only be called once.
     * @param initStorage The initial storage values.
     * Any call with a function signature not present in this contract will be delegated to the fallback contract.
     */
    function initializeStorage(InitStorage calldata initStorage) external;

    /**
     * @notice Updates the protocol's storage from V1 to V2.
     * @dev This specifically re-assigns the value for `sdexBurnOnDepositRatio` to a new storage slot.
     * It can only be called once and should only be called if the protocol was initially deployed as V1.
     */
    function initializeStorageV2() external;
}

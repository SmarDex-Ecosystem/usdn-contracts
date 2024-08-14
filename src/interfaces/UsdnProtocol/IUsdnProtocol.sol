// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import { IUsdnProtocolFallback } from "./IUsdnProtocolFallback.sol";
import { IUsdnProtocolImpl } from "./IUsdnProtocolImpl.sol";

/**
 * @title IUsdnProtocol
 * @notice Interface for the USDN protocol and fallback
 */
interface IUsdnProtocol is IUsdnProtocolImpl, IUsdnProtocolFallback {
    /**
     * @notice Function to upgrade the protocol to a new implementation (check {UUPSUpgradeable})
     * @dev This function should be called by the role with the PROXY_UPGRADE_ROLE
     * Passing in empty data skips the delegatecall to `newImplementation`
     * @param newImplementation The address of the new implementation
     * @param data The data to call when upgrading to the new implementation
     */
    function upgradeToAndCall(address newImplementation, bytes calldata data) external payable;
}

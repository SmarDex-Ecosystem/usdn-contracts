// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import { IUsdnProtocolErrors } from "./IUsdnProtocolErrors.sol";
import { IUsdnProtocolEvents } from "./IUsdnProtocolEvents.sol";
import { IUsdnProtocolFallback } from "./IUsdnProtocolFallback.sol";
import { IUsdnProtocolImpl } from "./IUsdnProtocolImpl.sol";

/**
 * @title IUsdnProtocol
 * @notice Interface for the USDN protocol and fallback.
 */
interface IUsdnProtocol is IUsdnProtocolImpl, IUsdnProtocolFallback, IUsdnProtocolErrors, IUsdnProtocolEvents {
    /**
     * @notice Upgrades the protocol to a new implementation (check
     * [UUPSUpgradeable](https://docs.openzeppelin.com/contracts/5.x/api/proxy#UUPSUpgradeable)).
     * @dev This function should be called by the role with the PROXY_UPGRADE_ROLE.
     * @param newImplementation The address of the new implementation.
     * @param data The data to call when upgrading to the new implementation. Passing in empty data skips the
     * delegatecall to `newImplementation`.
     */
    function upgradeToAndCall(address newImplementation, bytes calldata data) external payable;
}

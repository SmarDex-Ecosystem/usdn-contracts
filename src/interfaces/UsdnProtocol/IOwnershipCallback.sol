// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import { IERC165 } from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

import { IUsdnProtocolTypes } from "./IUsdnProtocolTypes.sol";

/**
 * @notice This interface can be implemented by contracts that wish to be notified when they become owner of a USDN
 * protocol position
 * @dev The contract must implement the ERC-165 interface detection mechanism
 */
interface IOwnershipCallback is IERC165 {
    /**
     * @notice This function is called by the USDN protocol on the new position owner after a transfer of ownership
     * @param oldOwner The previous owner of the position
     * @param posId The unique position identifier
     */
    function ownershipCallback(address oldOwner, IUsdnProtocolTypes.PositionId calldata posId) external;
}

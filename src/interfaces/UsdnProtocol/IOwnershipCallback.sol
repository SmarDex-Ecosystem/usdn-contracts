// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import { IERC165 } from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

import { IUsdnProtocolTypes as Types } from "./IUsdnProtocolTypes.sol";

/**
 * @notice This interface can be implemented by contracts that wish to be notified when they become owner of a USDN
 * protocol position.
 * @dev The contract must implement the ERC-165 interface detection mechanism.
 */
interface IOwnershipCallback is IERC165 {
    /**
     * @notice Called by the USDN protocol on the new position owner after an ownership transfer occurs.
     * @dev Implementers can use this callback to perform actions triggered by the ownership change.
     * @param oldOwner The address of the previous position owner.
     * @param posId The unique position identifier.
     */
    function ownershipCallback(address oldOwner, Types.PositionId calldata posId) external;
}

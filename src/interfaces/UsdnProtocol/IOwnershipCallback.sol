// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import { PositionId } from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";

interface IOwnershipCallback {
    /**
     * @notice This function is called by the USDN protocol on the new position owner after a transfer of ownership
     * @param oldOwner The previous owner of the position
     * @param posId The unique position identifier
     */
    function ownershipCallback(address oldOwner, PositionId calldata posId) external;
}

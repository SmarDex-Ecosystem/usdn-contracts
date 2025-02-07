// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import { Usdn } from "../../Usdn/Usdn.sol";
import { IRebaseCallback } from "../Usdn/IRebaseCallback.sol";

interface ISetRebaseHandlerManager {
    /**
     * @notice Gets the USDN token.
     * @return usdn_ The USDN token.
     */
    function USDN() external view returns (Usdn usdn_);

    /**
     * @notice Sets the rebase handler for the USDN token.
     * @param newHandler The address of the new rebase handler.
     */
    function setRebaseHandler(IRebaseCallback newHandler) external;

    /// @notice Revokes the DEFAULT_ADMIN_ROLE on the USDN token.
    function renounceUsdnOwnership() external;
}

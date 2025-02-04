// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Ownable2Step } from "@openzeppelin/contracts/access/Ownable2Step.sol";

import { Usdn } from "../Usdn/Usdn.sol";
import { IRebaseCallback } from "../interfaces/Usdn/IRebaseCallback.sol";

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

    /**
     * @notice Revokes the DEFAULT_ADMIN_ROLE on the USDN token.
     */
    function renounceUsdnOwnership() external;
}

/**
 * @title SetRebaseHandlerManager.
 * @notice The contract provides only the ability to set the rebase handler for the USDN token.
 */
contract SetRebaseHandlerManager is ISetRebaseHandlerManager, Ownable2Step {
    /// @inheritdoc ISetRebaseHandlerManager
    Usdn public immutable USDN;

    /**
     * @param usdn The address of the USDN token contract.
     * @param owner The address of the owner.
     */
    constructor(Usdn usdn, address owner) Ownable(owner) {
        USDN = usdn;
    }

    /// @inheritdoc ISetRebaseHandlerManager
    function setRebaseHandler(IRebaseCallback newHandler) external onlyOwner {
        USDN.setRebaseHandler(newHandler);
    }

    /// @inheritdoc ISetRebaseHandlerManager
    function renounceUsdnOwnership() external onlyOwner {
        USDN.revokeRole(0x00, address(this));
    }
}

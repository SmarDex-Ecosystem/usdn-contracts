// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Ownable2Step } from "@openzeppelin/contracts/access/Ownable2Step.sol";

import { IRebaseCallback } from "../interfaces/Usdn/IRebaseCallback.sol";
import { IUsdn } from "../interfaces/Usdn/IUsdn.sol";

/**
 * @title SetRebaseHandlerManager.
 * @notice The contract provides only the ability to set the rebase handler for the USDN token.
 */
contract SetRebaseHandlerManager is Ownable2Step {
    // The USDN token contract.
    IUsdn public immutable USDN;

    /**
     * @param usdn The address of the USDN token contract.
     * @param owner The address of the owner.
     */
    constructor(IUsdn usdn, address owner) Ownable(owner) {
        USDN = usdn;
    }

    /**
     * @notice Sets the rebase handler for the USDN token.
     * @param newHandler The address of the new rebase handler.
     */
    function setRebaseHandler(IRebaseCallback newHandler) external onlyOwner {
        USDN.setRebaseHandler(newHandler);
    }
}

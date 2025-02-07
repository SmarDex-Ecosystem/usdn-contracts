// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Ownable2Step } from "@openzeppelin/contracts/access/Ownable2Step.sol";

import { Usdn } from "../Usdn/Usdn.sol";
import { IRebaseCallback } from "../interfaces/Usdn/IRebaseCallback.sol";
import { ISetRebaseHandlerManager } from "../interfaces/Utils/ISetRebaseHandlerManager.sol";

/**
 * @notice This contract is meant to be the DefaultAdmin role of the USDN token, and it should only have the ability to
 * set the rebase handler.
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
        USDN.renounceRole(USDN.DEFAULT_ADMIN_ROLE(), address(this));
    }
}

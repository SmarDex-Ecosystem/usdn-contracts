// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { IUsdnProtocolTypes as Types } from "../../src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";

/**
 * @title Interface containing event signatures from various external contracts
 */
interface IEventsErrors {
    /* --------------------------------- IERC20 --------------------------------- */
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    /* ------------------------------- ERC20Permit ------------------------------ */
    error ERC2612ExpiredSignature(uint256 deadline);
    error ERC2612InvalidSigner(address signer, address owner);

    /* ----------------------------- IRebaseCallback ---------------------------- */
    event TestCallback();

    error RebaseHandlerFailure();

    /* ----------------------------- IOwnershipCallback ---------------------------- */

    event TestOwnershipCallback(address oldOwner, Types.PositionId posId);

    error OwnershipCallbackFailure();
}

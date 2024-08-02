// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { ERC165 } from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import { IERC165 } from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

import { IEventsErrors } from "../../../utils/IEventsErrors.sol";

import { IOwnershipCallback } from "../../../../src/interfaces/UsdnProtocol/IOwnershipCallback.sol";
import { IUsdnProtocolTypes as Types } from "../../../../src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";

/// @dev Mock handler for ownership transfer
contract OwnershipCallbackHandler is ERC165, IOwnershipCallback, IEventsErrors {
    bool public shouldFail;

    function supportsInterface(bytes4 interfaceId) public view override(ERC165, IERC165) returns (bool) {
        return interfaceId == type(IOwnershipCallback).interfaceId || super.supportsInterface(interfaceId);
    }

    function ownershipCallback(address oldOwner, Types.PositionId calldata posId) external {
        if (shouldFail) {
            revert OwnershipCallbackFailure();
        }
        emit TestOwnershipCallback(oldOwner, posId);
    }

    function setShouldFail(bool newValue) external {
        shouldFail = newValue;
    }
}

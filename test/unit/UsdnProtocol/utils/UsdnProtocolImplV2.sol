// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import { UsdnProtocolImpl } from "../../../../src/UsdnProtocol/UsdnProtocolImpl.sol";
import { UsdnProtocolUtilsLibrary as Utils } from "../../../../src/UsdnProtocol/libraries/UsdnProtocolUtilsLibrary.sol";
import { IUsdnProtocolImplV2 } from "./IUsdnProtocolImplV2.sol";

/// @custom:oz-upgrades-from UsdnProtocolImpl
contract UsdnProtocolImplV2 is UsdnProtocolImpl, IUsdnProtocolImplV2 {
    uint256 public newVariable;

    function initializeV2(address newFallback) public reinitializer(2) {
        Storage storage s = Utils._getMainStorage();

        newVariable = 1;
        s._protocolFallbackAddr = newFallback;
    }

    function retBool() public pure returns (bool) {
        return true;
    }
}

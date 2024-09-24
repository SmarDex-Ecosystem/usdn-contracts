// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import { IUsdnProtocolImpl } from "../../../../src/interfaces/UsdnProtocol/IUsdnProtocolImpl.sol";

interface IUsdnProtocolImplV2 is IUsdnProtocolImpl {
    function initializeV2(address newFallback) external;

    function retBool() external pure returns (bool);
}

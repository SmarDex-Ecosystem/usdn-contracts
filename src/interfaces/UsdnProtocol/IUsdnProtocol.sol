// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import { IUsdnProtocolActions } from "./IUsdnProtocolActions.sol";
import { IUsdnProtocolCore } from "./IUsdnProtocolCore.sol";
import { IUsdnProtocolLong } from "./IUsdnProtocolLong.sol";
import { IUsdnProtocolSetters } from "./IUsdnProtocolSetters.sol";
import { IUsdnProtocolStorage } from "./IUsdnProtocolStorage.sol";
import { IUsdnProtocolVault } from "./IUsdnProtocolVault.sol";

/**
 * @title IUsdnProtocol
 * @notice Interface for the USDN protocol
 */
interface IUsdnProtocol is
    IUsdnProtocolStorage,
    IUsdnProtocolActions,
    IUsdnProtocolVault,
    IUsdnProtocolLong,
    IUsdnProtocolCore,
    IUsdnProtocolSetters
{
    // TO DO : remove when the proxy is implemented
    function setSettersContract(address newSettersContract) external;
}

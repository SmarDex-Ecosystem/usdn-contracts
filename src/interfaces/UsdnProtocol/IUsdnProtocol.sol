// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import { IUsdnProtocolFallback } from "./IUsdnProtocolFallback.sol";
import { IUsdnProtocolImpl } from "./IUsdnProtocolImpl.sol";

/**
 * @title IUsdnProtocol
 * @notice Interface for the USDN protocol and fallback
 */
interface IUsdnProtocol is IUsdnProtocolImpl, IUsdnProtocolFallback { }

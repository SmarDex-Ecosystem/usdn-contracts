// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import { IUsdnProtocol } from "./IUsdnProtocol.sol";
import { IUsdnProtocolFallback } from "./IUsdnProtocolFallback.sol";

/**
 * @title IUsdnProtocolWithFallback
 * @notice Interface for the USDN protocol and fallback
 */
interface IUsdnProtocolWithFallback is IUsdnProtocol, IUsdnProtocolFallback { }

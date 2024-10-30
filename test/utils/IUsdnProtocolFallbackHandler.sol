// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import { IUsdnProtocolFallback } from "../../src/interfaces/UsdnProtocol/IUsdnProtocolFallback.sol";

/**
 * @title IUsdnProtocolFallbackHandler
 * @dev Interface for the USDN protocol fallback handler
 */
interface IUsdnProtocolFallbackHandler is IUsdnProtocolFallback {
    function i_setUsdnRebaseThreshold(uint128 threshold) external;
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { Test } from "forge-std/Test.sol";

import { UsdnProtocolFallback } from "../../../../src/UsdnProtocol/UsdnProtocolFallback.sol";

/**
 * @title UsdnProtocolFallbackHandler
 * @dev Wrapper to aid in testing the protocol
 */
contract UsdnProtocolFallbackHandler is UsdnProtocolFallback, Test {
    function i_setUsdnRebaseThreshold(uint128 threshold) external {
        s._usdnRebaseThreshold = threshold;
    }
}

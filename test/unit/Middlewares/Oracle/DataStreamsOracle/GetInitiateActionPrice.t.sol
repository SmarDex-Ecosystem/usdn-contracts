// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { OracleMiddlewareWithChainlinkDataStreamsFixture } from "../../utils/Fixtures.sol";
// import { IVerifierFeeManager } from "../../utils/MockStreamVerifierProxy.sol";

import { IFeeManager } from "../../../../../src/interfaces/OracleMiddleware/IFeeManager.sol";

/// @custom:feature The `_getInitiateActionPrice` function of the `OracleMiddlewareWithChainlinkDataStreams`.
contract TestOracleMiddlewareWithChainlinkDataStreamsInitiateActionPrice is
    OracleMiddlewareWithChainlinkDataStreamsFixture
{
    function setUp() public {
        _setUp();
    }

    /**
     * @custom:scenario Tests the `_getInitiateActionPrice` function.
     * @custom:when The function is called.
     * @custom:then .
     */
    function test_getInitiateActionPrice() public { }
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { MOCK_PYTH_DATA } from "../../utils/Constants.sol";
import { OracleMiddlewareWithDataStreamsFixture } from "../../utils/Fixtures.sol";

/// @custom:feature The `validationCost` function of the `OracleMiddlewareWithDataStreams`.
contract TestOracleMiddlewareWithDataStreamsValidationCost is OracleMiddlewareWithDataStreamsFixture {
    function setUp() public override {
        super.setUp();
    }

    /**
     * @custom:scenario Tests the `validationCost` with Chainlink onchain.
     * @custom:when The function is called.
     * @custom:then The fee must be equal 0.
     */
    function test_validationCostWithChainlinkOnchain() public view {
        bytes[] memory pythUpdateFees = new bytes[](1);
        pythUpdateFees[0] = MOCK_PYTH_DATA;

        uint256 fee = oracleMiddleware.validationCost("", actions[0]);
        assertEq(fee, 0, "Invalid Chainlink onchain fee");
    }

    /**
     * @custom:scenario Tests the `validationCost` with a Pyth data.
     * @custom:when The function is called.
     * @custom:then The fee must be equal to the Pyth fee.
     */
    function test_validationCostWithPyth() public view {
        bytes[] memory pythUpdateFees = new bytes[](1);
        pythUpdateFees[0] = MOCK_PYTH_DATA;

        uint256 fee = oracleMiddleware.validationCost(MOCK_PYTH_DATA, actions[0]);
        assertEq(fee, mockPyth.getUpdateFee(pythUpdateFees), "Invalid Pyth fee");
    }

    /**
     * @custom:scenario Tests the `validationCost` with a Chainlink data stream payload.
     * @custom:when The function is called.
     * @custom:then The fee must be equal to the report native fee.
     */
    function test_validationCostWithDataStream() public view {
        uint256 fee = oracleMiddleware.validationCost(payload, actions[0]);
        assertEq(fee, report.nativeFee, "Invalid Chainlink data stream fee");
    }
}

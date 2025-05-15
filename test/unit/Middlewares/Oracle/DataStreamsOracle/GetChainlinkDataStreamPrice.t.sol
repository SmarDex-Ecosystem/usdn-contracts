// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { MOCK_STREAM_V3, MOCK_STREAM_V4 } from "../../utils/Constants.sol";
import { OracleMiddlewareWithDataStreamsFixture } from "../../utils/Fixtures.sol";

import { FormattedDataStreamsPrice } from "../../../../../src/interfaces/OracleMiddleware/IOracleMiddlewareTypes.sol";

/// @custom:feature The `_getChainlinkDataStreamPrice` function of the `ChainlinkDataStreamsOracle`.
contract TestChainlinkDataStreamsOracleGetPrice is OracleMiddlewareWithDataStreamsFixture {
    function setUp() public override {
        super.setUp();
    }

    /**
     * @custom:scenario Tests the `_getChainlinkDataStreamPrice` function with a large fee.
     * @custom:when The function is called with a large fee.
     * @custom:then The call should revert with `OracleMiddlewareDataStreamFeeSafeguard`.
     */
    function test_RevertWhen_getChainlinkDataStreamPriceFeeSafeguard() public {
        report.nativeFee = type(uint192).max;
        (, payload) = _encodeReport(report);
        vm.expectRevert(abi.encodeWithSelector(OracleMiddlewareDataStreamFeeSafeguard.selector, report.nativeFee));
        oracleMiddleware.i_getChainlinkDataStreamPrice(payload, 0, 0);
    }

    /**
     * @custom:scenario Tests the `_getChainlinkDataStreamPrice` function with an incorrect fee.
     * @custom:when The function is called with an incorrect fee.
     * @custom:then The call should revert with `OracleMiddlewareIncorrectFee`.
     */
    function test_RevertWhen_getChainlinkDataStreamPriceIncorrectFee() public {
        vm.expectRevert(OracleMiddlewareIncorrectFee.selector);
        oracleMiddleware.i_getChainlinkDataStreamPrice{ value: report.nativeFee + 1 }(payload, 0, 0);
    }

    /**
     * @custom:scenario Tests the `_getChainlinkDataStreamPrice` function with an invalid report version.
     * @custom:when The function is called with an invalid report version.
     * @custom:then The call should revert with `OracleMiddlewareInvalidReportVersion`.
     */
    function test_RevertWhen_getChainlinkDataStreamPriceIncorrectReportVersion() public {
        report.feedId = MOCK_STREAM_V4;
        (, payload) = _encodeReport(report);
        vm.expectRevert(OracleMiddlewareInvalidReportVersion.selector);
        oracleMiddleware.i_getChainlinkDataStreamPrice{ value: report.nativeFee }(payload, 0, 0);
    }

    /**
     * @custom:scenario Tests the `_getChainlinkDataStreamPrice` function with an invalid stream id.
     * @custom:when The function is called  with an invalid stream id.
     * @custom:then The call should revert with `OracleMiddlewareInvalidStreamId`.
     */
    function test_RevertWhen_getChainlinkDataStreamPriceInvalidStreamId() public {
        report.feedId = bytes32(uint256(MOCK_STREAM_V3) | 1);
        (, payload) = _encodeReport(report);
        vm.expectRevert(OracleMiddlewareInvalidStreamId.selector);
        oracleMiddleware.i_getChainlinkDataStreamPrice{ value: report.nativeFee }(payload, 0, 0);
    }

    /**
     * @custom:scenario Tests the `_getChainlinkDataStreamPrice` function with an invalid timestamp
     * payload that lacks a target timestamp.
     * @custom:when The function is called.
     * @custom:then The call should revert with `OracleMiddlewareDataStreamInvalidTimestamp`.
     */
    function test_RevertWhen_getChainlinkDataStreamPriceInvalidTimestampWithoutTargetTimestamp() public {
        report.validFromTimestamp = 0;
        (, payload) = _encodeReport(report);
        vm.expectRevert(OracleMiddlewareDataStreamInvalidTimestamp.selector);
        oracleMiddleware.i_getChainlinkDataStreamPrice{ value: report.nativeFee }(payload, 0, 0);
    }

    /**
     * @custom:scenario Tests the `_getChainlinkDataStreamPrice` function with an invalid timestamp
     * payload and a target timestamp that is lower than the report's `validFromTimestamp`.
     * @custom:when The function is called.
     * @custom:then The call should revert with `OracleMiddlewareDataStreamInvalidTimestamp`.
     */
    function test_RevertWhen_getChainlinkDataStreamPriceInvalidTimestampWithTargetTimestampLtValidFromTimestamp()
        public
    {
        vm.expectRevert(OracleMiddlewareDataStreamInvalidTimestamp.selector);
        oracleMiddleware.i_getChainlinkDataStreamPrice{ value: report.nativeFee }(
            payload, report.validFromTimestamp - 1, 0
        );
    }

    /**
     * @custom:scenario Tests the `_getChainlinkDataStreamPrice` function with an invalid timestamp
     * payload and a target timestamp that is greater than the report's `observationsTimestamp`.
     * @custom:when The function is called.
     * @custom:then The call should revert with `OracleMiddlewareDataStreamInvalidTimestamp`.
     */
    function test_RevertWhen_getChainlinkDataStreamPriceInvalidTimestampWithTargetTimestampGtObservationsTimestamp()
        public
    {
        vm.expectRevert(OracleMiddlewareDataStreamInvalidTimestamp.selector);
        oracleMiddleware.i_getChainlinkDataStreamPrice{ value: report.nativeFee }(
            payload, report.observationsTimestamp + 1, 0
        );
    }

    /**
     * @custom:scenario Tests the `_getChainlinkDataStreamPrice` function with an invalid timestamp
     * payload and a target limit that is lower than the report's `observationsTimestamp`.
     * @custom:when The function is called.
     * @custom:then The call should revert with `OracleMiddlewareDataStreamInvalidTimestamp`.
     */
    function test_RevertWhen_getChainlinkDataStreamPriceInvalidTimestampWithTargetLimitLtObservationsTimestamp()
        public
    {
        vm.expectRevert(OracleMiddlewareDataStreamInvalidTimestamp.selector);
        oracleMiddleware.i_getChainlinkDataStreamPrice{ value: report.nativeFee }(
            payload, report.validFromTimestamp, report.observationsTimestamp - 1
        );
    }

    /**
     * @custom:scenario Tests the `_getChainlinkDataStreamPrice` function with a report price equal to zero.
     * @custom:when The function is called.
     * @custom:then The call should revert with `OracleMiddlewareWrongPrice`.
     */
    function test_RevertWhen_getChainlinkDataStreamPriceInvalidTimestampWithInvalidPrice() public {
        report.price = 0;
        (, payload) = _encodeReport(report);
        vm.expectRevert(abi.encodeWithSelector(OracleMiddlewareWrongPrice.selector, report.price));
        oracleMiddleware.i_getChainlinkDataStreamPrice{ value: report.nativeFee }(payload, 0, 0);
    }

    /**
     * @custom:scenario Tests the `_getChainlinkDataStreamPrice` function with a report ask price equal to zero.
     * @custom:when The function is called.
     * @custom:then The call should revert with `OracleMiddlewareWrongAskPrice`.
     */
    function test_RevertWhen_getChainlinkDataStreamPriceInvalidTimestampWithInvalidAskPrice() public {
        report.ask = 0;
        (, payload) = _encodeReport(report);
        vm.expectRevert(abi.encodeWithSelector(OracleMiddlewareWrongAskPrice.selector, report.ask));
        oracleMiddleware.i_getChainlinkDataStreamPrice{ value: report.nativeFee }(payload, 0, 0);
    }

    /**
     * @custom:scenario Tests the `_getChainlinkDataStreamPrice` function with a report bid price equal to zero.
     * @custom:when The function is called.
     * @custom:then The call should revert with `OracleMiddlewareWrongBidPrice`.
     */
    function test_RevertWhen_getChainlinkDataStreamPriceInvalidTimestampWithInvalidBidPrice() public {
        report.bid = 0;
        (, payload) = _encodeReport(report);
        vm.expectRevert(abi.encodeWithSelector(OracleMiddlewareWrongBidPrice.selector, report.bid));
        oracleMiddleware.i_getChainlinkDataStreamPrice{ value: report.nativeFee }(payload, 0, 0);
    }

    /**
     * @custom:scenario Tests the `_getChainlinkDataStreamPrice` function.
     * @custom:when The function is called.
     * @custom:then The verified report must match the Chainlink data streams report.
     */
    function test_getChainlinkDataStreamPrice() public {
        FormattedDataStreamsPrice memory formattedReport =
            oracleMiddleware.i_getChainlinkDataStreamPrice{ value: report.nativeFee }(payload, 0, 0);

        assertEq(formattedReport.timestamp, report.observationsTimestamp, "Invalid observationsTimestamp");
        assertEq(int192(int256(formattedReport.price)), report.price, "Invalid price");
        assertEq(int192(int256(formattedReport.bid)), report.bid, "Invalid bid");
        assertEq(int192(int256(formattedReport.ask)), report.ask, "Invalid ask");
    }
}

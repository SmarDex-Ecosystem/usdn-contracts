// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { EMPTY_STREAM_V3, EMPTY_STREAM_V4 } from "../../utils/Constants.sol";
import { OracleMiddlewareWithDataStreamsFixture } from "../../utils/Fixtures.sol";

import { FormattedDataStreamsPrice } from "../../../../../src/interfaces/OracleMiddleware/IOracleMiddlewareTypes.sol";

/// @custom:feature The `_getChainlinkDataStreamPrice` function of the `ChainlinkDataStreamsOracle`.
contract TestChainlinkDataStreamsOracleGetPrice is OracleMiddlewareWithDataStreamsFixture {
    function setUp() public override {
        super.setUp();
    }

    /**
     * @custom:scenario Tests the `_getChainlinkDataStreamPrice` function with a large fee.
     * @custom:when The function is called.
     * @custom:then It should revert with `OracleMiddlewareDataStreamFeeSafeguard`.
     */
    function test_RevertWhen_getChainlinkDataStreamPriceFeeSafeguard() public {
        report.nativeFee = type(uint192).max;
        (, payload) = _encodeReport(report);
        vm.expectRevert(abi.encodeWithSelector(OracleMiddlewareDataStreamFeeSafeguard.selector, report.nativeFee));
        oracleMiddleware.i_getChainlinkDataStreamPrice(payload, 0, 0);
    }

    /**
     * @custom:scenario Tests the `_getChainlinkDataStreamPrice` function with a incorrect fee.
     * @custom:when The function is called.
     * @custom:then It should revert with `OracleMiddlewareIncorrectFee`.
     */
    function test_RevertWhen_getChainlinkDataStreamPriceIncorrectFee() public {
        vm.expectRevert(OracleMiddlewareIncorrectFee.selector);
        oracleMiddleware.i_getChainlinkDataStreamPrice{ value: report.nativeFee + 1 }(payload, 0, 0);
    }

    /**
     * @custom:scenario Tests the `_getChainlinkDataStreamPrice` function with a incorrect report version.
     * @custom:when The function is called.
     * @custom:then It should revert with `OracleMiddlewareInvalidReportVersion`.
     */
    function test_RevertWhen_getChainlinkDataStreamPriceIncorrectReportVersion() public {
        report.feedId = EMPTY_STREAM_V4;
        (, payload) = _encodeReport(report);
        vm.expectRevert(OracleMiddlewareInvalidReportVersion.selector);
        oracleMiddleware.i_getChainlinkDataStreamPrice{ value: report.nativeFee }(payload, 0, 0);
    }

    /**
     * @custom:scenario Tests the `_getChainlinkDataStreamPrice` function with a invalid stream id.
     * @custom:when The function is called.
     * @custom:then It should revert with `OracleMiddlewareInvalidStreamId`.
     */
    function test_RevertWhen_getChainlinkDataStreamPriceInvalidStreamId() public {
        report.feedId = bytes32(uint256(EMPTY_STREAM_V3) | 1);
        (, payload) = _encodeReport(report);
        vm.expectRevert(OracleMiddlewareInvalidStreamId.selector);
        oracleMiddleware.i_getChainlinkDataStreamPrice{ value: report.nativeFee }(payload, 0, 0);
    }

    /**
     * @custom:scenario Tests the `_getChainlinkDataStreamPrice` function with a invalid timestamp
     * payload without target timestamp.
     * @custom:when The function is called.
     * @custom:then It should revert with `OracleMiddlewareDataStreamInvalidTimestamp`.
     */
    function test_RevertWhen_getChainlinkDataStreamPriceInvalidTimestampWithoutTargetTimestamp() public {
        report.validFromTimestamp = 0;
        (, payload) = _encodeReport(report);
        vm.expectRevert(OracleMiddlewareDataStreamInvalidTimestamp.selector);
        oracleMiddleware.i_getChainlinkDataStreamPrice{ value: report.nativeFee }(payload, 0, 0);
    }

    /**
     * @custom:scenario Tests the `_getChainlinkDataStreamPrice` function with a invalid timestamp
     * payload and a target timestamp lower than the report `validFromTimestamp`.
     * @custom:when The function is called.
     * @custom:then It should revert with `OracleMiddlewareDataStreamInvalidTimestamp`.
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
     * @custom:scenario Tests the `_getChainlinkDataStreamPrice` function with a invalid timestamp
     * payload and a target timestamp greater than the report `observationsTimestamp`.
     * @custom:when The function is called.
     * @custom:then It should revert with `OracleMiddlewareDataStreamInvalidTimestamp`.
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
     * @custom:scenario Tests the `_getChainlinkDataStreamPrice` function with a invalid timestamp
     * payload and a target limit lower than the report `observationsTimestamp`.
     * @custom:when The function is called.
     * @custom:then It should revert with `OracleMiddlewareDataStreamInvalidTimestamp`.
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
     * @custom:scenario Tests the `_getChainlinkDataStreamPrice` function with a report price equal zero.
     * @custom:when The function is called.
     * @custom:then It should revert with `OracleMiddlewareWrongPrice`.
     */
    function test_RevertWhen_getChainlinkDataStreamPriceInvalidTimestampWithInvalidPrice() public {
        report.price = 0;
        (, payload) = _encodeReport(report);
        vm.expectRevert(abi.encodeWithSelector(OracleMiddlewareWrongPrice.selector, report.price));
        oracleMiddleware.i_getChainlinkDataStreamPrice{ value: report.nativeFee }(payload, 0, 0);
    }

    /**
     * @custom:scenario Tests the `_getChainlinkDataStreamPrice` function with a report ask price equal zero.
     * @custom:when The function is called.
     * @custom:then It should revert with `OracleMiddlewareWrongAskPrice`.
     */
    function test_RevertWhen_getChainlinkDataStreamPriceInvalidTimestampWithInvalidAskPrice() public {
        report.ask = 0;
        (, payload) = _encodeReport(report);
        vm.expectRevert(abi.encodeWithSelector(OracleMiddlewareWrongAskPrice.selector, report.ask));
        oracleMiddleware.i_getChainlinkDataStreamPrice{ value: report.nativeFee }(payload, 0, 0);
    }

    /**
     * @custom:scenario Tests the `_getChainlinkDataStreamPrice` function with a report bid price equal zero.
     * @custom:when The function is called.
     * @custom:then It should revert with `OracleMiddlewareWrongBidPrice`.
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
     * @custom:then The transaction must be successful.
     * @custom:and The verified report must be equal to the report.
     * @custom:and The fee manager weth balance must be equal to the report nativeFee value.
     */
    function test_getChainlinkDataStreamPrice() public {
        FormattedDataStreamsPrice memory formattedReport =
            oracleMiddleware.i_getChainlinkDataStreamPrice{ value: report.nativeFee }(payload, 0, 0);

        assertEq(formattedReport.timestamp, report.observationsTimestamp, "Invalid observationsTimestamp");
        assertEq(int192(int256(formattedReport.price)), report.price, "Invalid price");
        assertEq(int192(int256(formattedReport.bid)), report.bid, "Invalid bid");
        assertEq(int192(int256(formattedReport.ask)), report.ask, "Invalid ask");
        assertEq(IERC20(wethTargetAddress).balanceOf(address(mockFeeManager)), report.nativeFee, "Wrong weth balance");
    }
}

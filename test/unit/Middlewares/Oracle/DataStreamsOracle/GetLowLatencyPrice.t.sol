// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { OracleMiddlewareWithDataStreamsFixture } from "../../utils/Fixtures.sol";

import { PriceAdjustment, PriceInfo } from "../../../../../src/interfaces/OracleMiddleware/IOracleMiddlewareTypes.sol";

/// @custom:feature The `_getLowLatencyPrice` function of the `OracleMiddlewareWithDataStreams`.
contract TestOracleMiddlewareWithDataStreamsGetLowLatencyPrice is OracleMiddlewareWithDataStreamsFixture {
    function setUp() public override {
        super.setUp();
    }

    /**
     * @custom:scenario Tests the `_getLowLatencyPrice` function without any adjustments.
     * @custom:when The function is called.
     * @custom:then The transaction must be successful.
     * @custom:and The returned price should match the report from the Chainlink data stream.
     */
    function test_getLowLatencyPrice() public {
        PriceInfo memory price =
            oracleMiddleware.i_getLowLatencyPrice{ value: report.nativeFee }(payload, 0, PriceAdjustment.None, 0);
        assertEq(int192(int256(price.price)), report.price, "Invalid price");
        assertEq(int192(int256(price.neutralPrice)), report.price, "Invalid neutral price");
        assertEq(uint32(price.timestamp), report.observationsTimestamp, "Invalid timestamp");
    }

    /**
     * @custom:scenario Tests the `_getLowLatencyPrice` function with an `Up` adjustment.
     * @custom:when The function is called.
     * @custom:then The transaction must be successful.
     * @custom:and The returned price should match the report from the Chainlink data stream.
     */
    function test_getLowLatencyPriceUp() public {
        PriceInfo memory price =
            oracleMiddleware.i_getLowLatencyPrice{ value: report.nativeFee }(payload, 0, PriceAdjustment.Up, 0);
        assertEq(int192(int256(price.price)), report.ask, "Invalid price");
        assertEq(int192(int256(price.neutralPrice)), report.price, "Invalid neutral price");
        assertEq(uint32(price.timestamp), report.observationsTimestamp, "Invalid timestamp");
    }

    /**
     * @custom:scenario Tests the `_getLowLatencyPrice` function with a `Down` adjustment.
     * @custom:when The function is called.
     * @custom:then The transaction must be successful.
     * @custom:and The returned price should match the report from the Chainlink data stream.
     */
    function test_getLowLatencyPriceDown() public {
        PriceInfo memory price =
            oracleMiddleware.i_getLowLatencyPrice{ value: report.nativeFee }(payload, 0, PriceAdjustment.Down, 0);
        assertEq(int192(int256(price.price)), report.bid, "Invalid price");
        assertEq(int192(int256(price.neutralPrice)), report.price, "Invalid neutral price");
        assertEq(uint32(price.timestamp), report.observationsTimestamp, "Invalid timestamp");
    }

    /**
     * @custom:scenario Tests the `_getLowLatencyPrice` function with timestamp values.
     * @custom:when The function is called.
     * @custom:then The transaction must be successful.
     * @custom:and The returned price must be valid for the given timestamps.
     */
    function test_getLowLatencyPriceWithTimestamp() public {
        PriceInfo memory price = oracleMiddleware.i_getLowLatencyPrice{ value: report.nativeFee }(
            payload,
            report.validFromTimestamp - uint128(oracleMiddleware.getValidationDelay()),
            PriceAdjustment.None,
            report.observationsTimestamp
        );
        assertEq(int192(int256(price.price)), report.price, "Invalid price");
        assertEq(int192(int256(price.neutralPrice)), report.price, "Invalid neutral price");
        assertEq(uint32(price.timestamp), report.observationsTimestamp, "Invalid timestamp");
    }
}

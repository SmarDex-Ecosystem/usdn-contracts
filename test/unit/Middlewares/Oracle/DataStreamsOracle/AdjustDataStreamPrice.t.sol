// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { OracleMiddlewareWithDataStreamsFixture } from "../../utils/Fixtures.sol";

import {
    FormattedDataStreamsPrice,
    PriceAdjustment,
    PriceInfo
} from "../../../../../src/interfaces/OracleMiddleware/IOracleMiddlewareTypes.sol";

/// @custom:feature The `_adjustDataStreamPrice` function of the `OracleMiddlewareWithDataStreams`.
contract TestOracleMiddlewareWithDataStreamsAdjustDataStream is OracleMiddlewareWithDataStreamsFixture {
    FormattedDataStreamsPrice internal formattedPrice;

    function setUp() public override {
        super.setUp();

        formattedPrice = FormattedDataStreamsPrice({
            timestamp: report.observationsTimestamp,
            price: uint192(report.price),
            ask: uint192(report.ask),
            bid: uint192(report.bid)
        });
    }

    /**
     * @custom:scenario Tests the `_adjustDataStreamPrice` without adjustment.
     * @custom:when The function is called without direction of the price adjustment.
     * @custom:then The returned price is the `price` attribute of the report.
     */
    function test_adjustDataStreamPriceWithoutAdjustment() public view {
        PriceInfo memory price = oracleMiddleware.i_adjustDataStreamPrice(formattedPrice, PriceAdjustment.None);
        assertEq(price.price, formattedPrice.price, "Invalid price");
        assertEq(price.neutralPrice, formattedPrice.price, "Invalid neutral price");
        assertEq(price.timestamp, formattedPrice.timestamp, "Invalid timestamp");
    }

    /**
     * @custom:scenario Tests the `_adjustDataStreamPrice` with a `Up` adjustment.
     * @custom:when The function is called with `Up` for the direction of the price adjustment.
     * @custom:then The returned price is the `ask` attribute of the report.
     */
    function test_adjustDataStreamPriceWithUpAdjustment() public view {
        PriceInfo memory price = oracleMiddleware.i_adjustDataStreamPrice(formattedPrice, PriceAdjustment.Up);
        assertEq(price.price, formattedPrice.ask, "Invalid price");
        assertEq(price.neutralPrice, formattedPrice.price, "Invalid neutral price");
        assertEq(price.timestamp, formattedPrice.timestamp, "Invalid timestamp");
    }

    /**
     * @custom:scenario Tests the `_adjustDataStreamPrice` with a `Down` adjustment.
     * @custom:when The function is called with `Down` for the direction of the price adjustment.
     * @custom:then The returned price is the `bid` attribute of the report.
     */
    function test_adjustDataStreamPriceWithDownAdjustment() public view {
        PriceInfo memory price = oracleMiddleware.i_adjustDataStreamPrice(formattedPrice, PriceAdjustment.Down);
        assertEq(price.price, formattedPrice.bid, "Invalid price");
        assertEq(price.neutralPrice, formattedPrice.price, "Invalid neutral price");
        assertEq(price.timestamp, formattedPrice.timestamp, "Invalid timestamp");
    }
}

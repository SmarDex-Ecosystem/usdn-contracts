// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { OracleMiddlewareWithChainlinkDataStreamsFixture } from "../../utils/Fixtures.sol";

import {
    FormattedDataStreamsPrice,
    PriceAdjustment,
    PriceInfo
} from "../../../../../src/interfaces/OracleMiddleware/IOracleMiddlewareTypes.sol";

/// @custom:feature The `_getLowLatencyPrice` function of the `OracleMiddlewareWithChainlinkDataStreams`.
contract TestOracleMiddlewareWithChainlinkDataStreamsAdjustDataStream is
    OracleMiddlewareWithChainlinkDataStreamsFixture
{
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
     * @custom:when The function is called.
     * @custom:then The price info must be returned as expected.
     */
    function test_adjustDataStreamPriceWithoutAdjustment() public view {
        PriceInfo memory price = oracleMiddleware.i_adjustDataStreamPrice(formattedPrice, PriceAdjustment.None);
        assertEq(price.price, formattedPrice.price, "Invalid price");
        assertEq(price.neutralPrice, formattedPrice.price, "Invalid neutral price");
        assertEq(price.timestamp, formattedPrice.timestamp, "Invalid timestamp");
    }

    /**
     * @custom:scenario Tests the `_adjustDataStreamPrice` with a up adjustment.
     * @custom:when The function is called.
     * @custom:then The price info must be returned as expected.
     */
    function test_adjustDataStreamPriceWithUpAdjustment() public view {
        PriceInfo memory price = oracleMiddleware.i_adjustDataStreamPrice(formattedPrice, PriceAdjustment.Up);
        assertEq(price.price, formattedPrice.ask, "Invalid price");
        assertEq(price.neutralPrice, formattedPrice.price, "Invalid neutral price");
        assertEq(price.timestamp, formattedPrice.timestamp, "Invalid timestamp");
    }

    /**
     * @custom:scenario Tests the `_adjustDataStreamPrice` with a down adjustment.
     * @custom:when The function is called.
     * @custom:then The price info must be returned as expected.
     */
    function test_adjustDataStreamPriceWithDownAdjustment() public view {
        PriceInfo memory price = oracleMiddleware.i_adjustDataStreamPrice(formattedPrice, PriceAdjustment.Down);
        assertEq(price.price, formattedPrice.bid, "Invalid price");
        assertEq(price.neutralPrice, formattedPrice.price, "Invalid neutral price");
        assertEq(price.timestamp, formattedPrice.timestamp, "Invalid timestamp");
    }
}

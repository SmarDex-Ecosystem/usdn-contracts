// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { FixedPointMathLib } from "solady/src/utils/FixedPointMathLib.sol";

import { MOCK_PYTH_DATA } from "../../utils/Constants.sol";
import { OracleMiddlewareWithDataStreamsFixture } from "../../utils/Fixtures.sol";

import { PriceInfo } from "../../../../../src/interfaces/OracleMiddleware/IOracleMiddlewareTypes.sol";

/// @custom:feature The `_getLiquidationPrice` function of the `OracleMiddlewareWithDataStreams`.
contract TestOracleMiddlewareWithDataStreamsGetLiquidationPrice is OracleMiddlewareWithDataStreamsFixture {
    function setUp() public override {
        super.setUp();
    }

    /**
     * @custom:scenario Tests the `_getLiquidationPrice` function using a Pyth price.
     * @custom:when The function is called.
     * @custom:then The returned price should match the price from Pyth.
     */
    function test_getLiquidationPriceWithPyth() public {
        bytes[] memory pythUpdateFees = new bytes[](1);
        pythUpdateFees[0] = MOCK_PYTH_DATA;
        uint256 pythUpdateFee = mockPyth.getUpdateFee(pythUpdateFees);

        uint256 scaleFactor = 10 ** (oracleMiddleware.getDecimals() - FixedPointMathLib.abs(mockPyth.expo()));
        uint256 pythPrice = uint256(uint64(mockPyth.price())) * scaleFactor;
        PriceInfo memory price = oracleMiddleware.i_getLiquidationPrice{ value: pythUpdateFee }(MOCK_PYTH_DATA);

        assertEq(price.price, pythPrice, "Invalid price");
        assertEq(price.neutralPrice, pythPrice, "Invalid neutral price");
        assertEq(price.timestamp, mockPyth.lastPublishTime(), "Invalid timestamp");
    }

    /**
     * @custom:scenario Tests the `_getLiquidationPrice` function using a Chainlink data stream price.
     * @custom:when The function is called.
     * @custom:then The returned price should match the report from the Chainlink data stream.
     */
    function test_getLiquidationPriceWithDatastream() public {
        PriceInfo memory price = oracleMiddleware.i_getLiquidationPrice{ value: report.nativeFee }(payload);
        assertEq(int192(int256(price.price)), report.price, "Invalid price");
        assertEq(int192(int256(price.neutralPrice)), report.price, "Invalid neutral price");
        assertEq(uint32(price.timestamp), report.observationsTimestamp, "Invalid timestamp");
    }
}

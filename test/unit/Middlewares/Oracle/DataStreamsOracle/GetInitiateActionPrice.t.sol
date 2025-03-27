// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { PythStructs } from "@pythnetwork/pyth-sdk-solidity/PythStructs.sol";
import { FixedPointMathLib } from "solady/src/utils/FixedPointMathLib.sol";

import { OracleMiddlewareWithDataStreamsFixture } from "../../utils/Fixtures.sol";

import { PriceAdjustment, PriceInfo } from "../../../../../src/interfaces/OracleMiddleware/IOracleMiddlewareTypes.sol";

/// @custom:feature The `_getInitiateActionPrice` function of the `OracleMiddlewareWithDataStreams`.
contract TestOracleMiddlewareWithDataStreamsGetInitiateActionPrice is OracleMiddlewareWithDataStreamsFixture {
    function setUp() public override {
        super.setUp();
    }

    /**
     * @custom:scenario Tests the `_getInitiateActionPrice` with chainlink data stream.
     * @custom:when The function is called.
     * @custom:then The price info must be equal to the data stream report.
     */
    function test_getInitiateActionPriceWithDataStream() public {
        PriceInfo memory price =
            oracleMiddleware.i_getInitiateActionPrice{ value: report.nativeFee }(payload, PriceAdjustment.None);

        assertEq(int192(int256(price.price)), report.price, "Invalid price");
        assertEq(int192(int256(price.neutralPrice)), report.price, "Invalid neutral price");
        assertEq(uint32(price.timestamp), report.observationsTimestamp, "Invalid timestamp");
    }

    /**
     * @custom:scenario Tests the `_getInitiateActionPrice` with a chainlink onchain price and a eth value.
     * @custom:when The function is called.
     * @custom:then It should revert with `OracleMiddlewareIncorrectFee`.
     */
    function test_RevertWhen_getInitiateActionPriceWithValue() public {
        vm.expectRevert(OracleMiddlewareIncorrectFee.selector);
        oracleMiddleware.i_getInitiateActionPrice{ value: 1 }("", PriceAdjustment.None);
    }

    /**
     * @custom:scenario Tests the `_getInitiateActionPrice` with a unsafe Pyth price and a old timestamp.
     * @custom:when The function is called.
     * @custom:then It should revert with `OracleMiddlewarePriceTooOld`.
     */
    function test_RevertWhen_getInitiateActionUnsafePythPriceTooOld() public {
        mockChainlinkOnChain.setLastPublishTime(0);
        mockPyth.setUnsafePrice(1);
        uint256 invalidPythTimestamp = block.timestamp - oracleMiddleware.getChainlinkTimeElapsedLimit() - 1;
        mockPyth.setLastPublishTime(invalidPythTimestamp);

        vm.expectRevert(abi.encodeWithSelector(OracleMiddlewarePriceTooOld.selector, invalidPythTimestamp));
        oracleMiddleware.i_getInitiateActionPrice("", PriceAdjustment.None);
    }

    /**
     * @custom:scenario Tests the `_getInitiateActionPrice` with a unsafe Pyth price.
     * @custom:when The function is called.
     * @custom:then The price info must be equal to the unsafe Pyth price.
     */
    function test_getInitiateActionPriceUnsafePyth() public {
        mockChainlinkOnChain.setLastPublishTime(0);
        int64 pythPrice = mockPyth.price();
        mockPyth.setUnsafePrice(pythPrice);
        uint256 validPythTimestamp = block.timestamp - oracleMiddleware.getChainlinkTimeElapsedLimit();
        mockPyth.setLastPublishTime(validPythTimestamp);

        PythStructs.Price memory unsafePythPrice = mockPyth.getPriceUnsafe("");
        PriceInfo memory price = oracleMiddleware.i_getInitiateActionPrice("", PriceAdjustment.None);

        uint256 scaleFactor = 10 ** (oracleMiddleware.getDecimals() - FixedPointMathLib.abs(unsafePythPrice.expo));
        uint256 scaledUnsafePythPrice = uint64(unsafePythPrice.price) * scaleFactor;

        assertEq(price.price, scaledUnsafePythPrice, "Invalid price");
        assertEq(price.neutralPrice, scaledUnsafePythPrice, "Invalid neutral price");
        assertEq(price.timestamp, unsafePythPrice.publishTime, "Invalid timestamp");
    }

    /**
     * @custom:scenario Tests the `_getInitiateActionPrice` with a old chainlink onchain price.
     * @custom:when The function is called.
     * @custom:then It should revert with `OracleMiddlewarePriceTooOld`.
     */
    function test_RevertWhen_getInitiateActionChainlinkPriceTooOld() public {
        uint256 invalidChainlinkTimestamp = block.timestamp - oracleMiddleware.getChainlinkTimeElapsedLimit() - 1;
        mockChainlinkOnChain.setLastPublishTime(invalidChainlinkTimestamp);

        vm.expectRevert(abi.encodeWithSelector(OracleMiddlewarePriceTooOld.selector, invalidChainlinkTimestamp));
        oracleMiddleware.i_getInitiateActionPrice("", PriceAdjustment.None);
    }

    /**
     * @custom:scenario Tests the `_getInitiateActionPrice` with a wrong chainlink onchain price.
     * @custom:when The function is called.
     * @custom:then It should revert with `OracleMiddlewareWrongPrice`.
     */
    function test_RevertWhen_getInitiateActionWrongPrice() public {
        int256 wrongChainlinkPrice = -1;
        mockChainlinkOnChain.setLastPrice(wrongChainlinkPrice);

        int256 scaleFactor = int256(10 ** (oracleMiddleware.getDecimals() - mockChainlinkOnChain.decimals()));

        vm.expectRevert(abi.encodeWithSelector(OracleMiddlewareWrongPrice.selector, wrongChainlinkPrice * scaleFactor));
        oracleMiddleware.i_getInitiateActionPrice("", PriceAdjustment.None);
    }

    /**
     * @custom:scenario Tests the `_getInitiateActionPrice` with chainlink onchain.
     * @custom:when The function is called.
     * @custom:then The price info must be equal to the chainlink onchain price.
     */
    function test_getInitiateActionPriceWithChainlinkOnchain() public {
        (, int256 chainlinkOnChainPrice,, uint256 timestamp,) = mockChainlinkOnChain.latestRoundData();

        uint256 adjustedPrice = uint256(chainlinkOnChainPrice)
            * 10 ** uint256(oracleMiddleware.getDecimals() - mockChainlinkOnChain.decimals());
        PriceInfo memory price = oracleMiddleware.i_getInitiateActionPrice("", PriceAdjustment.None);

        assertEq(price.price, adjustedPrice, "Invalid price");
        assertEq(price.neutralPrice, adjustedPrice, "Invalid neutral price");
        assertEq(price.timestamp, timestamp, "Invalid timestamp");
    }
}

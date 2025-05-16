// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { FixedPointMathLib } from "solady/src/utils/FixedPointMathLib.sol";

import { MOCK_PYTH_DATA } from "../../utils/Constants.sol";
import { WstethOracleWithDataStreamsBaseFixture } from "../../utils/Fixtures.sol";

import { PriceInfo } from "../../../../../src/interfaces/OracleMiddleware/IOracleMiddlewareTypes.sol";
import { IUsdnProtocolTypes as Types } from "../../../../../src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";

/**
 * @custom:feature The `parseAndValidatePrice` function of the `WstethOracleWithDataStreams`
 * @custom:background A deployed `WstethOracleWithDataStreams` contract.
 */
contract TestWstethOracleParseAndValidatePrice is WstethOracleWithDataStreamsBaseFixture {
    uint256 internal oracleFee;

    function setUp() public override {
        super.setUp();
    }

    /**
     * @custom:scenario Tests the `parseAndValidatePrice` with a payload from a Chainlink data stream.
     * @custom:when The function is called.
     * @custom:then The returned price data must be equal to the data from the Chainlink data stream report.
     */
    function test_parseAndValidatePriceWithDataStreams() public {
        oracleFee = oracleMiddleware.validationCost(payload, Types.ProtocolAction.InitiateOpenPosition);

        PriceInfo memory price = oracleMiddleware.parseAndValidatePrice{ value: oracleFee }(
            "", 0, Types.ProtocolAction.InitiateOpenPosition, payload
        );

        assertEq(price.price, uint192(report.price), "The returned price must be equal to the report price");
        assertEq(
            price.neutralPrice, uint192(report.price), "The returned neutral price must be equal to the report price"
        );
        assertEq(
            price.timestamp,
            uint128(report.observationsTimestamp),
            "The returned timestamp must be equal to the report observationsTimestamp"
        );
    }

    /**
     * @custom:scenario Tests the `parseAndValidatePrice` with a price data from a Pyth price feed.
     * @custom:when The function is called.
     * @custom:then The returned price data must be equal to the adjusted data from the Pyth price feed.
     */
    function test_parseAndValidatePriceWithPyth() public {
        oracleFee = oracleMiddleware.validationCost(MOCK_PYTH_DATA, Types.ProtocolAction.Liquidation);

        PriceInfo memory price = oracleMiddleware.parseAndValidatePrice{ value: oracleFee }(
            "", 0, Types.ProtocolAction.Liquidation, MOCK_PYTH_DATA
        );
        uint256 adjustedWstethPythPrice = uint256(uint64(mockPyth.price()))
            * 10 ** (oracleMiddleware.getDecimals() - FixedPointMathLib.abs(mockPyth.expo())) * wsteth.stEthPerToken()
            / 1 ether;

        assertEq(price.price, adjustedWstethPythPrice, "The returned price must be equal to the adjusted Pyth price");
        assertEq(
            price.neutralPrice,
            adjustedWstethPythPrice,
            "The returned neutral price must be equal to the adjusted Pyth price"
        );
        assertEq(
            price.timestamp, mockPyth.lastPublishTime(), "The returned timestamp must be equal to the Pyth timestamp"
        );
    }

    /**
     * @custom:scenario Tests the `parseAndValidatePrice` without data.
     * @custom:when The function is called.
     * @custom:then The returned price data must be equal to the adjusted data from the latest roundId of the Chainlink
     * data feeds.
     */
    function test_parseAndValidatePriceWithDataFeedsEmptyData() public {
        oracleFee = oracleMiddleware.validationCost("", Types.ProtocolAction.InitiateOpenPosition);

        (, int256 answer,, uint256 updatedAt,) = mockChainlinkOnChain.latestRoundData();
        PriceInfo memory price = oracleMiddleware.parseAndValidatePrice{ value: oracleFee }(
            "", 0, Types.ProtocolAction.InitiateOpenPosition, ""
        );
        uint256 adjustedWstethDataFeedsPrice = uint256(answer)
            * 10 ** (oracleMiddleware.getDecimals() - mockChainlinkOnChain.decimals()) * wsteth.stEthPerToken() / 1 ether;
        assertEq(
            price.price,
            adjustedWstethDataFeedsPrice,
            "The returned price must be equal to the adjusted latest roundId adjusted price"
        );
        assertEq(
            price.neutralPrice,
            adjustedWstethDataFeedsPrice,
            "The returned neutral price must be equal to the adjusted latest roundId adjusted price"
        );
        assertEq(price.timestamp, updatedAt, "The returned timestamp must be equal to the latest roundId timestamp");
    }

    /**
     * @custom:scenario Tests the `parseAndValidatePrice` with a specified roundId data from a Chainlink data feed.
     * @custom:when The function is called.
     * @custom:then The returned price data must be equal to the adjusted data from the specified
     * roundId of the Chainlink data feeds.
     */
    function test_parseAndValidatePriceWithDataFeedsRoundIdData() public {
        uint256 lowLatencyDelay = oracleMiddleware.getLowLatencyDelay();
        skip(lowLatencyDelay + 1);

        uint80 roundId = 1;
        (,,, uint256 previousRoundIdTimestamp,) = mockChainlinkOnChain.getRoundData(roundId - 1);

        mockChainlinkOnChain.setRoundTimestamp(
            roundId, previousRoundIdTimestamp + oracleMiddleware.getLowLatencyDelay() + 1
        );
        oracleFee = oracleMiddleware.validationCost(abi.encode(roundId), Types.ProtocolAction.ValidateOpenPosition);

        (, int256 answer,, uint256 updatedAt,) = mockChainlinkOnChain.getRoundData(roundId);
        PriceInfo memory price = oracleMiddleware.parseAndValidatePrice{ value: oracleFee }(
            "", uint128(previousRoundIdTimestamp), Types.ProtocolAction.ValidateOpenPosition, abi.encode(roundId)
        );
        uint256 adjustedWstethDataFeedsPrice = uint256(answer)
            * 10 ** (oracleMiddleware.getDecimals() - mockChainlinkOnChain.decimals()) * wsteth.stEthPerToken() / 1 ether;

        assertEq(
            price.price,
            adjustedWstethDataFeedsPrice,
            "The returned price must be equal to the specified roundId adjusted price"
        );
        assertEq(
            price.neutralPrice,
            adjustedWstethDataFeedsPrice,
            "The returned neutral price must be equal to the specified roundId adjusted price"
        );
        assertEq(price.timestamp, updatedAt, "The returned timestamp must be equal to specified roundId timestamp");
    }
}

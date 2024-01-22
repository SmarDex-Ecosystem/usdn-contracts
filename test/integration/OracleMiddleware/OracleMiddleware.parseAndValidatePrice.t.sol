// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { console2 } from "forge-std/Test.sol";

import { OracleMiddlewareBaseFixture } from "test/integration/OracleMiddleware/utils/Fixtures.sol";
import { PYTH_WSTETH_USD } from "test/utils/Constants.sol";

import { IOracleMiddlewareErrors, PriceInfo, ProtocolAction } from "src/interfaces/IOracleMiddleware.sol";

/**
 * @custom:feature The `parseAndValidatePrice` function of `OracleMiddleware`
 * @custom:background Given the price of ETH is 2000 USD
 * @custom:and The confidence interval is 20 USD
 */
contract TestOracleMiddlewareParseAndValidatePriceRealData is OracleMiddlewareBaseFixture, IOracleMiddlewareErrors {
    function setUp() public override {
        super.setUp();
    }

    /* -------------------------------------------------------------------------- */
    /*                                 Without FFI                                */
    /* -------------------------------------------------------------------------- */

    /**
     * @custom:scenario Parse and validate price with mocked hermes API signature
     * @custom:given The price feed is wstETH/USD
     * @custom:and The validationDelay is respected
     * @custom:when Protocol action is `None`
     * @custom:then The price signature is well decoded
     * @custom:and The price retrived by the oracle middleware is the same as the one from the hermes API
     */
    function test_parseAndValidatePriceWithPythDataAndNoneAction() public ethMainnetFork {
        super.setUp();
        (uint256 pythPrice,, uint256 pythTimestamp, bytes memory data) = super.getMockedPythSignature();

        PriceInfo memory middlewarePrice = oracleMiddleware.parseAndValidatePrice{ value: 1 ether }(
            uint128(pythTimestamp - oracleMiddleware.validationDelay()), ProtocolAction.None, data
        );

        assertEq(middlewarePrice.timestamp, pythTimestamp);
        assertEq(
            middlewarePrice.price * 10 ** oracleMiddleware.pythDecimals() / 10 ** oracleMiddleware.decimals(), pythPrice
        );
    }

    /**
     * @custom:scenario Parse and validate price with mocked hermes API signature
     * @custom:given The price feed is wstETH/USD
     * @custom:and The validationDelay is respected
     * @custom:when Protocol action is `ValidateDeposit`
     * @custom:then The price signature is well decoded
     * @custom:and The price retrived by the oracle middleware is equals to the
     *             one from the hermes API - the confidence interval.
     */
    function test_parseAndValidatePriceWithPythDataAndValidateDepositAction() public ethMainnetFork {
        super.setUp();
        (uint256 pythPrice, uint256 pythConf, uint256 pythTimestamp, bytes memory data) = super.getMockedPythSignature();

        PriceInfo memory middlewarePrice = oracleMiddleware.parseAndValidatePrice{ value: 1 ether }(
            uint128(pythTimestamp - oracleMiddleware.validationDelay()), ProtocolAction.ValidateDeposit, data
        );

        assertEq(middlewarePrice.timestamp, pythTimestamp);
        assertEq(
            middlewarePrice.price * 10 ** oracleMiddleware.pythDecimals() / 10 ** oracleMiddleware.decimals(),
            pythPrice - pythConf
        );
    }

    /**
     * @custom:scenario Parse and validate price with real hermes API signature
     * @custom:given The price feed is wstETH/USD
     * @custom:and The validationDelay is respected
     * @custom:when Protocol action is `ValidateOpenPosition`
     * @custom:then The price signature is well decoded
     * @custom:and The price retrived by the oracle middleware is equals to the
     *             one from the hermes API + the confidence interval.
     */
    function test_parseAndValidatePriceWithPythDataAndValidateOpenPositionAction() public ethMainnetFork {
        super.setUp();
        (uint256 pythPrice, uint256 pythConf, uint256 pythTimestamp, bytes memory data) = super.getMockedPythSignature();

        PriceInfo memory middlewarePrice = oracleMiddleware.parseAndValidatePrice{ value: 1 ether }(
            uint128(pythTimestamp - oracleMiddleware.validationDelay()), ProtocolAction.ValidateOpenPosition, data
        );

        assertEq(middlewarePrice.timestamp, pythTimestamp);
        assertEq(
            middlewarePrice.price * 10 ** oracleMiddleware.pythDecimals() / 10 ** oracleMiddleware.decimals(),
            pythPrice + pythConf
        );
    }

    /* -------------------------------------------------------------------------- */
    /*                                  With FFI                                  */
    /* -------------------------------------------------------------------------- */

    /**
     * @custom:scenario Parse and validate price with real hermes API signature
     * @custom:given The price feed is wstETH/USD
     * @custom:and The validationDelay is respected
     * @custom:when Protocol action is `None`
     * @custom:then The price signature is well decoded
     * @custom:and The price retrived by the oracle middleware is the same as the one from the hermes API
     */
    function test_FFI_parseAndValidatePriceWithPythDataAndNoneAction() public ethMainnetFork {
        super.setUp();
        (uint256 pythPrice,, uint256 pythTimestamp, bytes memory data) =
            super.getHermesApiSignature(PYTH_WSTETH_USD, block.timestamp);

        PriceInfo memory middlewarePrice = oracleMiddleware.parseAndValidatePrice{ value: 1 ether }(
            uint128(block.timestamp - oracleMiddleware.validationDelay()), ProtocolAction.None, data
        );

        assertEq(middlewarePrice.timestamp, pythTimestamp);
        assertEq(
            middlewarePrice.price * 10 ** oracleMiddleware.pythDecimals() / 10 ** oracleMiddleware.decimals(), pythPrice
        );
    }

    /**
     * @custom:scenario Parse and validate price with real hermes API signature
     * @custom:given The price feed is wstETH/USD
     * @custom:and The validationDelay is respected
     * @custom:when Protocol action is `ValidateDeposit`
     * @custom:then The price signature is well decoded
     * @custom:and The price retrived by the oracle middleware is equals to the
     *             one from the hermes API - the confidence interval.
     */
    function test_FFI_parseAndValidatePriceWithPythDataAndValidateDepositAction() public ethMainnetFork {
        super.setUp();
        (uint256 pythPrice, uint256 pythConf, uint256 pythTimestamp, bytes memory data) =
            super.getHermesApiSignature(PYTH_WSTETH_USD, block.timestamp);

        PriceInfo memory middlewarePrice = oracleMiddleware.parseAndValidatePrice{ value: 1 ether }(
            uint128(block.timestamp - oracleMiddleware.validationDelay()), ProtocolAction.ValidateDeposit, data
        );

        assertEq(middlewarePrice.timestamp, pythTimestamp);
        assertEq(
            middlewarePrice.price * 10 ** oracleMiddleware.pythDecimals() / 10 ** oracleMiddleware.decimals(),
            pythPrice - pythConf
        );
    }

    /**
     * @custom:scenario Parse and validate price with real hermes API signature
     * @custom:given The price feed is wstETH/USD
     * @custom:and The validationDelay is respected
     * @custom:when Protocol action is `ValidateOpenPosition`
     * @custom:then The price signature is well decoded
     * @custom:and The price retrived by the oracle middleware is equals to the
     *             one from the hermes API + the confidence interval.
     */
    function test_FFI_parseAndValidatePriceWithPythDataAndValidateOpenPositionAction() public ethMainnetFork {
        super.setUp();
        (uint256 pythPrice, uint256 pythConf, uint256 pythTimestamp, bytes memory data) =
            super.getHermesApiSignature(PYTH_WSTETH_USD, block.timestamp);

        PriceInfo memory middlewarePrice = oracleMiddleware.parseAndValidatePrice{ value: 1 ether }(
            uint128(block.timestamp - oracleMiddleware.validationDelay()), ProtocolAction.ValidateOpenPosition, data
        );

        assertEq(middlewarePrice.timestamp, pythTimestamp);
        assertEq(
            middlewarePrice.price * 10 ** oracleMiddleware.pythDecimals() / 10 ** oracleMiddleware.decimals(),
            pythPrice + pythConf
        );
    }

    /**
     * @custom:scenario Parse and validate price using chainlink onchain
     * @custom:given The price feed is wstETH/USD
     * @custom:and The validationDelay is respected
     * @custom:when Protocol action is `InitiateDeposit`
     * @custom:then The price signature is well decoded
     * @custom:and The price retrived by the oracle middleware is equals to the
     *             one from the chainlink on chain contract.
     */
    function test_FFI_parseAndValidatePriceWithPythDataAndInitiateDepositAction() public ethMainnetFork {
        super.setUp();
        (uint256 chainlinkPrice, uint256 chainlinkTimestamp) = super.getChainlinkPrice();

        PriceInfo memory middlewarePrice = oracleMiddleware.parseAndValidatePrice{ value: 1 ether }(
            uint128(block.timestamp - oracleMiddleware.validationDelay()),
            ProtocolAction.InitiateDeposit,
            abi.encode("")
        );

        assertEq(middlewarePrice.timestamp, chainlinkTimestamp);
        assertEq(
            middlewarePrice.price * 10 ** oracleMiddleware.chainlinkDecimals() / 10 ** oracleMiddleware.decimals(),
            chainlinkPrice
        );
    }
}

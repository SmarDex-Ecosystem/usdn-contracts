// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { OracleMiddlewareBaseFixture } from "test/integration/OracleMiddleware/utils/Fixtures.sol";
import { ActionsIntegrationTests } from "test/integration/OracleMiddleware/utils/ActionsIntegrationTests.sol";
import { PYTH_WSTETH_USD } from "test/utils/Constants.sol";

import { IOracleMiddlewareErrors, PriceInfo, ProtocolAction } from "src/interfaces/IOracleMiddleware.sol";
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";

/**
 * @custom:feature The `parseAndValidatePrice` function of `OracleMiddleware`
 * @custom:background Given the price of ETH is 2000 USD
 * @custom:and The confidence interval is 20 USD
 * @custom:and The oracles are not mocked
 */
contract TestOracleMiddlewareParseAndValidatePriceRealData is
    OracleMiddlewareBaseFixture,
    IOracleMiddlewareErrors,
    ActionsIntegrationTests
{
    using Strings for uint256;

    function setUp() public override {
        super.setUp();
    }

    /* -------------------------------------------------------------------------- */
    /*                                 Without FFI                                */
    /* -------------------------------------------------------------------------- */

    /**
     * @custom:scenario Parse and validate price with mocked hermes API signature for pyth
     * or with chainlink onchain
     * @custom:given The price feed is wstETH/USD for pyth and steth/usd for chainlink
     * @custom:and The validationDelay is respected
     * @custom:when Protocol action is any targeted action
     * @custom:then The price signature is well decoded
     * @custom:and The price retrieved by the oracle middleware is the same as the one from the hermes API or chainlink
     * onchain data
     */
    function test_ForkparseAndValidatePriceForAllActions() public ethMainnetFork reSetUp {
        // all targeted actions loop
        for (uint256 i; i < actions.length; i++) {
            // action type
            ProtocolAction action = actions[i];

            // timestamp error message
            string memory timestampError =
                string.concat("Wrong oracle middleware timestamp for action: ", uint256(action).toString());
            // price error message
            string memory priceError =
                string.concat("Wrong oracle middleware price for action: ", uint256(action).toString());

            // chainlink case
            if (action == ProtocolAction.InitiateDeposit) {
                // chainlink data
                (uint256 chainlinkPrice, uint256 chainlinkTimestamp) = super.getChainlinkPrice();
                // middleware data
                PriceInfo memory middlewarePrice = oracleMiddleware.parseAndValidatePrice{ value: 1 ether }(
                    uint128(block.timestamp - oracleMiddleware.validationDelay()), action, abi.encode("")
                );
                // timestamp check
                assertEq(middlewarePrice.timestamp, chainlinkTimestamp, timestampError);
                // price check
                assertEq(
                    middlewarePrice.price * 10 ** oracleMiddleware.chainlinkDecimals()
                        / 10 ** oracleMiddleware.decimals(),
                    chainlinkPrice,
                    priceError
                );
            } else {
                // pyth data
                (uint256 pythPrice, uint256 pythConf, uint256 pythTimestamp, bytes memory data) =
                    super.getMockedPythSignature();

                // middleware data
                PriceInfo memory middlewarePrice = oracleMiddleware.parseAndValidatePrice{ value: 1 ether }(
                    uint128(pythTimestamp - oracleMiddleware.validationDelay()), action, data
                );

                // timestamp check
                assertEq(middlewarePrice.timestamp, pythTimestamp);

                // formatted middleware price
                uint256 middlewareFormattedPrice =
                    middlewarePrice.price * 10 ** oracleMiddleware.pythDecimals() / 10 ** oracleMiddleware.decimals();

                // Price + conf
                if (action == ProtocolAction.ValidateOpenPosition) {
                    // check price
                    assertEq(middlewareFormattedPrice, pythPrice + pythConf, priceError);

                    // Price - conf
                } else if (action == ProtocolAction.ValidateDeposit) {
                    // check price
                    assertEq(middlewareFormattedPrice, pythPrice - pythConf, priceError);

                    // Price only
                } else {
                    // check price
                    assertEq(middlewareFormattedPrice, pythPrice, priceError);
                }
            }
        }
    }

    /* -------------------------------------------------------------------------- */
    /*                                  With FFI                                  */
    /* -------------------------------------------------------------------------- */

    /**
     * @custom:scenario Parse and validate price with mocked hermes API signature for pyth
     * or with chainlink onchain
     * @custom:given The price feed is wstETH/USD for pyth and steth/usd for chainlink
     * @custom:and The validationDelay is respected
     * @custom:when Protocol action is any targeted action
     * @custom:then The price signature is well decoded
     * @custom:and The price retrieved by the oracle middleware is the same as the one from the hermes API or chainlink
     * onchain data
     */
    function test_ForkFFIparseAndValidatePriceForAllActions() public ethMainnetFork reSetUp {
        // all targeted actions loop
        for (uint256 i; i < actions.length; i++) {
            // action type
            ProtocolAction action = actions[i];

            // timestamp error message
            string memory timestampError =
                string.concat("Wrong oracle middleware timestamp for action: ", uint256(action).toString());
            // price error message
            string memory priceError =
                string.concat("Wrong oracle middleware price for action: ", uint256(action).toString());

            // chainlink case
            if (action == ProtocolAction.InitiateDeposit) {
                // chainlink data
                (uint256 chainlinkPrice, uint256 chainlinkTimestamp) = super.getChainlinkPrice();
                // middleware data
                PriceInfo memory middlewarePrice = oracleMiddleware.parseAndValidatePrice{ value: 1 ether }(
                    uint128(block.timestamp - oracleMiddleware.validationDelay()), action, abi.encode("")
                );
                // timestamp check
                assertEq(middlewarePrice.timestamp, chainlinkTimestamp, timestampError);
                // price check
                assertEq(
                    middlewarePrice.price * 10 ** oracleMiddleware.chainlinkDecimals()
                        / 10 ** oracleMiddleware.decimals(),
                    chainlinkPrice,
                    priceError
                );
            } else {
                // pyth data
                (uint256 pythPrice, uint256 pythConf, uint256 pythTimestamp, bytes memory data) =
                    super.getHermesApiSignature(PYTH_WSTETH_USD, block.timestamp);

                // middleware data
                PriceInfo memory middlewarePrice = oracleMiddleware.parseAndValidatePrice{ value: 1 ether }(
                    uint128(pythTimestamp - oracleMiddleware.validationDelay()), action, data
                );

                // timestamp check
                assertEq(middlewarePrice.timestamp, pythTimestamp);

                // formatted middleware price
                uint256 middlewareFormattedPrice =
                    middlewarePrice.price * 10 ** oracleMiddleware.pythDecimals() / 10 ** oracleMiddleware.decimals();

                // Price + conf
                if (action == ProtocolAction.ValidateOpenPosition) {
                    // check price
                    assertEq(middlewareFormattedPrice, pythPrice + pythConf, priceError);

                    // Price - conf
                } else if (action == ProtocolAction.ValidateDeposit) {
                    // check price
                    assertEq(middlewareFormattedPrice, pythPrice - pythConf, priceError);

                    // Price only
                } else {
                    // check price
                    assertEq(middlewareFormattedPrice, pythPrice, priceError);
                }
            }
        }
    }
}

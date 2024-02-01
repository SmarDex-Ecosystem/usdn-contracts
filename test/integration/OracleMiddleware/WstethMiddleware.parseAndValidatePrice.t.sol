// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { WstethFixtures } from "test/integration/OracleMiddleware/utils/WstethFixtures.sol";
import { ActionsIntegrationTests } from "test/integration/OracleMiddleware/utils/ActionsIntegrationTests.sol";
import { PYTH_WSTETH_USD, PYTH_STETH_USD } from "test/utils/Constants.sol";

import { IOracleMiddlewareErrors, PriceInfo, ProtocolAction } from "src/interfaces/IOracleMiddleware.sol";
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";

/**
 * @custom:feature The `parseAndValidatePrice` function of `WstethMiddleware`
 * @custom:background Given the price of STETH is ~1739 USD
 * @custom:and The confidence interval is 20 USD
 * @custom:and The oracles are not mocked
 */
contract TestWstethMiddlewareParseAndValidatePriceRealData is
    WstethFixtures,
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
     * @custom:given The price feed is stETH/USD for pyth and chainlink
     * @custom:and The validationDelay is respected
     * @custom:when Protocol action is any targeted action
     * @custom:then The price signature is well decoded
     * @custom:and The price retrieved by the oracle middleware is the same as the one from the hermes API or chainlink
     * onchain data by applying Steth/Wsteth onchain price ratio.
     */
    function test_ForkWstethparseAndValidatePriceForAllActions() public ethMainnetFork reSetUp {
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
                PriceInfo memory middlewarePrice = wstethMiddleware.parseAndValidatePrice{ value: 1 ether }(
                    uint128(block.timestamp - wstethMiddleware.validationDelay()), action, abi.encode("")
                );
                // timestamp check
                assertEq(middlewarePrice.timestamp, chainlinkTimestamp, timestampError);
                // price check
                assertEq(
                    middlewarePrice.price,
                    stethToWsteth(
                        chainlinkPrice * 10 ** wstethMiddleware.decimals() / 10 ** wstethMiddleware.chainlinkDecimals()
                    ),
                    priceError
                );
            } else {
                // pyth data
                (uint256 pythPrice, uint256 pythConf, uint256 pythTimestamp, bytes memory data) =
                    super.getMockedPythSignature();

                // middleware data
                PriceInfo memory middlewarePrice = wstethMiddleware.parseAndValidatePrice{ value: 1 ether }(
                    uint128(pythTimestamp - wstethMiddleware.validationDelay()), action, data
                );

                // timestamp check
                assertEq(middlewarePrice.timestamp, pythTimestamp);

                // formatted pyth price
                uint256 formattedPythPrice =
                    pythPrice * 10 ** wstethMiddleware.decimals() / 10 ** wstethMiddleware.pythDecimals();

                // formatted pyth conf
                uint256 formattedPythConf =
                    pythConf * 10 ** wstethMiddleware.decimals() / 10 ** wstethMiddleware.pythDecimals();

                // Price + conf
                if (action == ProtocolAction.ValidateOpenPosition) {
                    // check price
                    assertEq(middlewarePrice.price, stethToWsteth(formattedPythPrice + formattedPythConf), priceError);

                    // Price - conf
                } else if (action == ProtocolAction.ValidateDeposit) {
                    // check price
                    assertEq(middlewarePrice.price, stethToWsteth(formattedPythPrice - formattedPythConf), priceError);

                    // Price only
                } else {
                    // check price
                    assertEq(middlewarePrice.price, stethToWsteth(formattedPythPrice), priceError);
                }
            }
        }
    }

    /* -------------------------------------------------------------------------- */
    /*                                  With FFI                                  */
    /* -------------------------------------------------------------------------- */

    /**
     * @custom:scenario Parse and validate price with real hermes API signature for pyth
     * or with chainlink onchain
     * @custom:given The price feed is stETH/USD for pyth and chainlink
     * @custom:and The validationDelay is respected
     * @custom:when Protocol action is any targeted action
     * @custom:then The price signature is well decoded
     * @custom:and The price retrieved by the oracle middleware is the same as the one from the hermes API or chainlink
     * onchain data by applying Steth/Wsteth onchain price ratio.
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
                PriceInfo memory middlewarePrice = wstethMiddleware.parseAndValidatePrice{ value: 1 ether }(
                    uint128(block.timestamp - wstethMiddleware.validationDelay()), action, abi.encode("")
                );
                // timestamp check
                assertEq(middlewarePrice.timestamp, chainlinkTimestamp, timestampError);
                // price check
                assertEq(
                    middlewarePrice.price,
                    stethToWsteth(
                        chainlinkPrice * 10 ** wstethMiddleware.decimals() / 10 ** wstethMiddleware.chainlinkDecimals()
                    ),
                    priceError
                );
            } else {
                // pyth data
                (uint256 pythPrice, uint256 pythConf, uint256 pythTimestamp, bytes memory data) =
                    super.getHermesApiSignature(PYTH_STETH_USD, block.timestamp);

                // middleware data
                PriceInfo memory middlewarePrice = wstethMiddleware.parseAndValidatePrice{ value: 1 ether }(
                    uint128(pythTimestamp - wstethMiddleware.validationDelay()), action, data
                );

                // timestamp check
                assertEq(middlewarePrice.timestamp, pythTimestamp);

                // formatted pyth price
                uint256 formattedPythPrice =
                    pythPrice * 10 ** wstethMiddleware.decimals() / 10 ** wstethMiddleware.pythDecimals();

                // formatted pyth conf
                uint256 formattedPythConf =
                    pythConf * 10 ** wstethMiddleware.decimals() / 10 ** wstethMiddleware.pythDecimals();

                // Price + conf
                if (action == ProtocolAction.ValidateOpenPosition) {
                    // check price
                    assertEq(middlewarePrice.price, stethToWsteth(formattedPythPrice + formattedPythConf), priceError);

                    // Price - conf
                } else if (action == ProtocolAction.ValidateDeposit) {
                    // check price
                    assertEq(middlewarePrice.price, stethToWsteth(formattedPythPrice - formattedPythConf), priceError);

                    // Price only
                } else {
                    // check price
                    assertEq(middlewarePrice.price, stethToWsteth(formattedPythPrice), priceError);

                    // pyth wsteth price comparison
                    (
                        uint256 pythWstethPrice,
                        uint256 pythWstethConf, // price difference should be less than conf
                        uint256 pythWstethTimestamp,
                    ) = super.getHermesApiSignature(PYTH_WSTETH_USD, block.timestamp);

                    assertEq(middlewarePrice.timestamp, pythWstethTimestamp, "Wrong similar timestamp");

                    // Should obtain a short differente price between pyth wsteth pricefeed
                    // and pyth steth pricefeed adjusted with ratio.
                    // We are ok with a delta below pyth wsteth confidence.
                    assertApproxEqAbs(
                        middlewarePrice.price,
                        pythWstethPrice * 10 ** wstethMiddleware.decimals() / 10 ** wstethMiddleware.pythDecimals(),
                        pythWstethConf * 10 ** wstethMiddleware.decimals() / 10 ** wstethMiddleware.pythDecimals(),
                        priceError
                    );
                }
            }
        }
    }
}

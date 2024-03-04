// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";

import { OracleMiddlewareBaseIntegrationFixture } from "test/integration/OracleMiddleware/utils/Fixtures.sol";
import { PYTH_WSTETH_USD } from "test/utils/Constants.sol";

import { ProtocolAction } from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import { PriceInfo } from "src/interfaces/OracleMiddleware/IOracleMiddlewareTypes.sol";

/**
 * @custom:feature The `parseAndValidatePrice` function of `OracleMiddleware`
 * @custom:background Given the price of ETH is 2000 USD
 * @custom:and The confidence interval is 20 USD
 * @custom:and The oracles are not mocked
 */
contract TestOracleMiddlewareParseAndValidatePriceRealData is OracleMiddlewareBaseIntegrationFixture {
    using Strings for uint256;

    function setUp() public override {
        super.setUp();
    }

    /* -------------------------------------------------------------------------- */
    /*                                 Without FFI                                */
    /* -------------------------------------------------------------------------- */

    /**
     * @custom:scenario Parse and validate price with mocked hermes API signature for pyth
     * @custom:given The price feed is wstETH/USD for pyth
     * @custom:and The validationDelay is respected
     * @custom:when Protocol action is any targeted action
     * @custom:then The price signature is well decoded
     * @custom:and The price retrieved by the oracle middleware is the same as the one from the hermes API
     */
    function test_ForkParseAndValidatePriceForAllActionsWithPyth() public ethMainnetFork reSetUp {
        // all targeted actions loop
        for (uint256 i; i < actions.length; i++) {
            // action type
            ProtocolAction action = actions[i];

            // price error message
            string memory priceError = string.concat("Wrong oracle middleware price for ", actionNames[i]);

            // pyth data
            (uint256 pythPrice, uint256 pythConf, uint256 pythTimestamp, bytes memory data) = getMockedPythSignature();
            // Apply conf ratio to pyth confidence
            pythConf = (pythConf * oracleMiddleware.getConfRatio()) / oracleMiddleware.getConfRatioDenom();

            // middleware data
            PriceInfo memory middlewarePrice;

            if (action == ProtocolAction.Liquidation) {
                // Pyth requires that the price data timestamp is recent compared to block.timestamp
                vm.warp(pythTimestamp);
                middlewarePrice = oracleMiddleware.parseAndValidatePrice{ value: 1 ether }(0, action, data);
            } else {
                middlewarePrice = oracleMiddleware.parseAndValidatePrice{ value: 1 ether }(
                    uint128(pythTimestamp - oracleMiddleware.validationDelay()), action, data
                );
            }

            // timestamp check
            assertEq(middlewarePrice.timestamp, pythTimestamp);

            // formatted middleware price
            uint256 middlewareFormattedPrice =
                middlewarePrice.price * 10 ** oracleMiddleware.pythDecimals() / 10 ** oracleMiddleware.decimals();

            // Price + conf
            if (action == ProtocolAction.ValidateOpenPosition) {
                // check price with approximation of 1 to prevent rounding errors
                assertApproxEqAbs(middlewareFormattedPrice, pythPrice + pythConf, 1, priceError);
            }
            // Price - conf
            else if (action == ProtocolAction.ValidateDeposit || action == ProtocolAction.ValidateClosePosition) {
                // check price with approximation of 1 to prevent rounding errors
                assertApproxEqAbs(middlewareFormattedPrice, pythPrice - pythConf, 1, priceError);
            }
            // Price only
            else {
                // check price
                assertEq(middlewareFormattedPrice, pythPrice, priceError);
            }
        }
    }

    /**
     * @custom:scenario Parse and validate price with chainlink onchain
     * @custom:given The price feed is steth/usd for chainlink
     * @custom:when Protocol action is any targeted action
     * @custom:then The price retrieved by the oracle middleware is the same as the one from chainlink onchain data
     */
    function test_ForkParseAndValidatePriceForAllInitiateActionsWithChainlink() public ethMainnetFork reSetUp {
        // all targeted actions loop
        for (uint256 i; i < actions.length; i++) {
            // action type
            ProtocolAction action = actions[i];

            // If the action is only available for pyth, skip it
            if (
                action == ProtocolAction.None || action == ProtocolAction.ValidateDeposit
                    || action == ProtocolAction.ValidateWithdrawal || action == ProtocolAction.ValidateOpenPosition
                    || action == ProtocolAction.ValidateClosePosition || action == ProtocolAction.Liquidation
            ) {
                continue;
            }

            // timestamp error message
            string memory timestampError = string.concat("Wrong oracle middleware timestamp for ", actionNames[i]);
            // price error message
            string memory priceError = string.concat("Wrong oracle middleware price for ", actionNames[i]);

            // chainlink data
            (uint256 chainlinkPrice, uint256 chainlinkTimestamp) = getChainlinkPrice();
            // middleware data
            PriceInfo memory middlewarePrice = oracleMiddleware.parseAndValidatePrice{ value: 1 ether }(
                uint128(block.timestamp - oracleMiddleware.validationDelay()), action, ""
            );
            // timestamp check
            assertEq(middlewarePrice.timestamp, chainlinkTimestamp, timestampError);
            // price check
            assertEq(
                (middlewarePrice.price * 10 ** oracleMiddleware.chainlinkDecimals()) / 10 ** oracleMiddleware.decimals(),
                chainlinkPrice,
                priceError
            );
        }
    }

    /* -------------------------------------------------------------------------- */
    /*                                  With FFI                                  */
    /* -------------------------------------------------------------------------- */

    /**
     * @custom:scenario Parse and validate price with mocked hermes API signature for pyth
     * @custom:given The price feed is wstETH/USD for pyth
     * @custom:and The validationDelay is respected
     * @custom:when Protocol action is any targeted action
     * @custom:then The price signature is well decoded
     * @custom:and The price retrieved by the oracle middleware is the same as the one from the hermes API
     */
    function test_ForkFFIParseAndValidatePriceForAllActionsWithPyth() public ethMainnetFork reSetUp {
        // all targeted actions loop
        for (uint256 i; i < actions.length; i++) {
            // action type
            ProtocolAction action = actions[i];

            // price error message
            string memory priceError = string.concat("Wrong oracle middleware price for ", actionNames[i]);

            // pyth data
            (uint256 pythPrice, uint256 pythConf, uint256 pythTimestamp, bytes memory data) =
                getHermesApiSignature(PYTH_WSTETH_USD, block.timestamp);
            // Apply conf ratio to pyth confidence
            pythConf = (pythConf * oracleMiddleware.getConfRatio()) / oracleMiddleware.getConfRatioDenom();

            // middleware data
            PriceInfo memory middlewarePrice;
            if (action == ProtocolAction.Liquidation) {
                // Pyth requires that the price data timestamp is recent compared to block.timestamp
                vm.warp(pythTimestamp);
                middlewarePrice = oracleMiddleware.parseAndValidatePrice{ value: 1 ether }(0, action, data);
            } else {
                middlewarePrice = oracleMiddleware.parseAndValidatePrice{ value: 1 ether }(
                    uint128(pythTimestamp - oracleMiddleware.validationDelay()), action, data
                );
            }

            // timestamp check
            assertEq(middlewarePrice.timestamp, pythTimestamp);

            // formatted middleware price
            uint256 middlewareFormattedPrice =
                middlewarePrice.price * 10 ** oracleMiddleware.pythDecimals() / 10 ** oracleMiddleware.decimals();

            // Price + conf
            if (action == ProtocolAction.ValidateOpenPosition) {
                // check price with approximation of 1 to prevent rounding errors
                assertApproxEqAbs(middlewareFormattedPrice, pythPrice + pythConf, 1, priceError);
            }
            // Price - conf
            else if (action == ProtocolAction.ValidateDeposit || action == ProtocolAction.ValidateClosePosition) {
                // check price with approximation of 1 to prevent rounding errors
                assertApproxEqAbs(middlewareFormattedPrice, pythPrice - pythConf, 1, priceError);
            }
            // Price only
            else {
                // check price
                assertEq(middlewareFormattedPrice, pythPrice, priceError);
            }
        }
    }

    /**
     * @custom:scenario Parse and validate price with chainlink onchain
     * @custom:given The price feed is steth/usd for chainlink
     * @custom:when Protocol action is an initiateDeposit
     * @custom:then The price signature is well decoded
     * @custom:and The price retrieved by the oracle middleware is the same as the one from the chainlink onchain data
     */
    function test_ForkFFIParseAndValidatePriceForAllInitiateActionsWithChainlink() public ethMainnetFork reSetUp {
        // all targeted actions loop
        for (uint256 i; i < actions.length; i++) {
            // action type
            ProtocolAction action = actions[i];

            // If the action is only available for pyth, skip it
            if (
                action == ProtocolAction.None || action == ProtocolAction.ValidateDeposit
                    || action == ProtocolAction.ValidateWithdrawal || action == ProtocolAction.ValidateOpenPosition
                    || action == ProtocolAction.ValidateClosePosition || action == ProtocolAction.Liquidation
            ) {
                continue;
            }

            // timestamp error message
            string memory timestampError = string.concat("Wrong oracle middleware timestamp for ", actionNames[i]);
            // price error message
            string memory priceError = string.concat("Wrong oracle middleware price for ", actionNames[i]);

            // chainlink data
            (uint256 chainlinkPrice, uint256 chainlinkTimestamp) = getChainlinkPrice();
            // middleware data
            PriceInfo memory middlewarePrice = oracleMiddleware.parseAndValidatePrice{ value: 1 ether }(
                uint128(block.timestamp - oracleMiddleware.validationDelay()), action, ""
            );
            // timestamp check
            assertEq(middlewarePrice.timestamp, chainlinkTimestamp, timestampError);
            // price check
            assertEq(
                (middlewarePrice.price * 10 ** oracleMiddleware.chainlinkDecimals()) / 10 ** oracleMiddleware.decimals(),
                chainlinkPrice,
                priceError
            );
        }
    }

    // receive ether refunds
    receive() external payable { }
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";

import { WstethIntegrationFixture } from "test/integration/Middlewares/utils/Fixtures.sol";
import { PYTH_WSTETH_USD, PYTH_ETH_USD } from "test/utils/Constants.sol";

import { PriceInfo } from "src/interfaces/OracleMiddleware/IOracleMiddlewareTypes.sol";
import { ProtocolAction } from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";

/**
 * @custom:feature The `parseAndValidatePrice` function of `WstethMiddleware`
 * @custom:background Given the price of ETH is ~1739 USD
 * @custom:and The confidence interval is 20 USD
 * @custom:and The oracles are not mocked
 */
contract TestWstethMiddlewareParseAndValidatePriceRealData is WstethIntegrationFixture {
    using Strings for uint256;

    function setUp() public override {
        super.setUp();
    }

    /* -------------------------------------------------------------------------- */
    /*                                 Without FFI                                */
    /* -------------------------------------------------------------------------- */

    /**
     * @custom:scenario Parse and validate price with mocked hermes API signature for pyth
     * @custom:given The price feed is ETH/USD for pyth and chainlink
     * @custom:and The validationDelay is respected
     * @custom:when The Protocol action is any targeted action
     * @custom:then The price signature is well-decoded
     * @custom:and The price retrieved by the oracle middleware is the same as the one from the hermes API by applying
     * Steth/Wsteth on-chain price ratio
     */
    function test_ForkEthParseAndValidatePriceForAllActionsWithPyth() public ethMainnetFork reSetUp {
        // all targeted actions loop
        for (uint256 i; i < actions.length; i++) {
            // action type
            ProtocolAction action = actions[i];

            // price error message
            string memory priceError =
                string.concat("Wrong oracle middleware price for action: ", uint256(action).toString());

            // pyth data
            (uint256 pythPrice, uint256 pythConf, uint256 pythDecimals, uint256 pythTimestamp, bytes memory data) =
                getMockedPythSignatureETH();

            // middleware data
            PriceInfo memory middlewarePrice;
            uint256 validationCost = wstethMiddleware.validationCost(data, action);
            if (
                action == ProtocolAction.Initialize || action == ProtocolAction.Liquidation
                    || action == ProtocolAction.InitiateDeposit || action == ProtocolAction.InitiateWithdrawal
                    || action == ProtocolAction.InitiateOpenPosition || action == ProtocolAction.InitiateClosePosition
            ) {
                // since we force the usage of Pyth for initiate actions, Pyth requires
                // that the price data timestamp is recent compared to block.timestamp
                vm.warp(pythTimestamp);
                middlewarePrice = wstethMiddleware.parseAndValidatePrice{ value: validationCost }("", 0, action, data);
            } else {
                middlewarePrice = wstethMiddleware.parseAndValidatePrice{ value: validationCost }(
                    "", uint128(pythTimestamp - wstethMiddleware.getValidationDelay()), action, data
                );
            }

            // timestamp check
            assertEq(middlewarePrice.timestamp, pythTimestamp);

            // formatted pyth price
            uint256 formattedPythPrice = pythPrice * 10 ** wstethMiddleware.getDecimals() / 10 ** pythDecimals;

            // apply conf ratio to pyth confidence
            uint256 formattedPythConf = (
                pythConf * 10 ** (wstethMiddleware.getDecimals() - pythDecimals) * wstethMiddleware.getConfRatioBps()
            ) / wstethMiddleware.BPS_DIVISOR();

            // price + conf
            if (
                action == ProtocolAction.InitiateWithdrawal || action == ProtocolAction.ValidateWithdrawal
                    || action == ProtocolAction.InitiateOpenPosition || action == ProtocolAction.ValidateOpenPosition
            ) {
                // check price
                assertEq(middlewarePrice.price, stethToWsteth(formattedPythPrice + formattedPythConf), priceError);

                // price - conf
            } else if (
                action == ProtocolAction.InitiateDeposit || action == ProtocolAction.ValidateDeposit
                    || action == ProtocolAction.InitiateClosePosition || action == ProtocolAction.ValidateClosePosition
            ) {
                // check price
                assertEq(middlewarePrice.price, stethToWsteth(formattedPythPrice - formattedPythConf), priceError);

                // price only
            } else {
                // check price
                assertEq(middlewarePrice.price, stethToWsteth(formattedPythPrice), priceError);
            }
        }
    }

    /**
     * @custom:scenario Parse and validate price with chainlink on-chain
     * @custom:given The price feed is ETH/USD for chainlink
     * @custom:when The Protocol action is any InitiateDeposit
     * @custom:then The price retrieved by the oracle middleware is the same as the one from the chainlink on-chain data
     * by applying Steth/Wsteth on-chain price ratio
     */
    function test_ForkEthParseAndValidatePriceForInitiateDepositWithChainlink() public ethMainnetFork reSetUp {
        // all targeted actions loop
        for (uint256 i; i < actions.length; i++) {
            // action type
            ProtocolAction action = actions[i];

            // if the action is only available for pyth, skip it
            if (
                action == ProtocolAction.None || action == ProtocolAction.ValidateDeposit
                    || action == ProtocolAction.ValidateWithdrawal || action == ProtocolAction.ValidateOpenPosition
                    || action == ProtocolAction.ValidateClosePosition || action == ProtocolAction.Liquidation
            ) {
                continue;
            }

            // timestamp error message
            string memory timestampError =
                string.concat("Wrong oracle middleware timestamp for action: ", uint256(action).toString());
            // price error message
            string memory priceError =
                string.concat("Wrong oracle middleware price for action: ", uint256(action).toString());

            // chainlink data
            (uint256 chainlinkPrice, uint256 chainlinkTimestamp) = getChainlinkPrice();
            // middleware data
            PriceInfo memory middlewarePrice =
                wstethMiddleware.parseAndValidatePrice("", uint128(block.timestamp), action, "");
            // timestamp check
            assertEq(middlewarePrice.timestamp, chainlinkTimestamp, timestampError);
            // price check
            assertEq(
                middlewarePrice.price,
                stethToWsteth(
                    chainlinkPrice * 10 ** wstethMiddleware.getDecimals()
                        / 10 ** wstethMiddleware.getChainlinkDecimals()
                ),
                priceError
            );
        }
    }

    /* -------------------------------------------------------------------------- */
    /*                                  With FFI                                  */
    /* -------------------------------------------------------------------------- */

    /**
     * @custom:scenario Parse and validate price with real hermes API signature for pyth
     * @custom:given The price feed is ETH/USD for pyth
     * @custom:and The validationDelay is respected
     * @custom:when The Protocol action is any targeted action
     * @custom:then The price signature is well-decoded
     * @custom:and The price retrieved by the oracle middleware is the same as the one from the hermes API by applying
     * Steth/Wsteth onchain price ratio
     */
    function test_ForkFFIParseAndValidatePriceForAllActionsWithPyth() public ethMainnetFork reSetUp {
        // all targeted actions loop
        for (uint256 i; i < actions.length; i++) {
            // action type
            ProtocolAction action = actions[i];

            // price error message
            string memory priceError =
                string.concat("Wrong oracle middleware price for action: ", uint256(action).toString());

            // pyth data
            (uint256 pythPrice, uint256 pythConf, uint256 pythDecimals, uint256 pythTimestamp, bytes memory data) =
                getHermesApiSignature(PYTH_ETH_USD, block.timestamp);

            // middleware data
            PriceInfo memory middlewarePrice;
            {
                uint256 validationCost = wstethMiddleware.validationCost(data, action);
                if (
                    action == ProtocolAction.Initialize || action == ProtocolAction.Liquidation
                        || action == ProtocolAction.InitiateDeposit || action == ProtocolAction.InitiateWithdrawal
                        || action == ProtocolAction.InitiateOpenPosition || action == ProtocolAction.InitiateClosePosition
                ) {
                    // since we force the usage of Pyth for initiate actions,
                    // Pyth requires that the price data timestamp is recent compared to block.timestamp
                    vm.warp(pythTimestamp);
                    middlewarePrice =
                        wstethMiddleware.parseAndValidatePrice{ value: validationCost }("", 0, action, data);
                } else {
                    middlewarePrice = wstethMiddleware.parseAndValidatePrice{ value: validationCost }(
                        "", uint128(pythTimestamp - wstethMiddleware.getValidationDelay()), action, data
                    );
                }
            }

            // timestamp check
            assertEq(middlewarePrice.timestamp, pythTimestamp);

            // formatted pyth price
            uint256 formattedPythPrice = pythPrice * 10 ** wstethMiddleware.getDecimals() / 10 ** pythDecimals;

            // apply conf ratio to pyth confidence
            uint256 formattedPythConf = (
                pythConf * 10 ** (wstethMiddleware.getDecimals() - pythDecimals) * wstethMiddleware.getConfRatioBps()
            ) / wstethMiddleware.BPS_DIVISOR();

            // price + conf
            if (
                action == ProtocolAction.InitiateWithdrawal || action == ProtocolAction.ValidateWithdrawal
                    || action == ProtocolAction.InitiateOpenPosition || action == ProtocolAction.ValidateOpenPosition
            ) {
                assertEq(middlewarePrice.price, stethToWsteth(formattedPythPrice + formattedPythConf), priceError);
            }
            // price - conf
            else if (
                action == ProtocolAction.InitiateDeposit || action == ProtocolAction.ValidateDeposit
                    || action == ProtocolAction.InitiateClosePosition || action == ProtocolAction.ValidateClosePosition
            ) {
                assertEq(middlewarePrice.price, stethToWsteth(formattedPythPrice - formattedPythConf), priceError);
            }
            // price only
            else {
                // check price
                assertEq(middlewarePrice.price, stethToWsteth(formattedPythPrice), priceError);

                // pyth wsteth price comparison
                (
                    uint256 pythWstethPrice,
                    uint256 pythWstethConf, // price difference should be less than conf
                    ,
                    uint256 pythWstethTimestamp,
                ) = getHermesApiSignature(PYTH_WSTETH_USD, block.timestamp);

                assertEq(middlewarePrice.timestamp, pythWstethTimestamp, "Wrong similar timestamp");

                // should obtain a short different price between the pyth wsteth price feed
                // and the pyth eth price feed adjusted with ratio.
                // We are ok with a delta below the pyth wsteth confidence.
                assertApproxEqAbs(
                    middlewarePrice.price,
                    pythWstethPrice * 10 ** wstethMiddleware.getDecimals() / 10 ** pythDecimals,
                    pythWstethConf * 10 ** wstethMiddleware.getDecimals() / 10 ** pythDecimals,
                    priceError
                );
            }
        }
    }

    /**
     * @custom:scenario Parse and validate price with chainlink on-chain
     * @custom:given The price feed is ETH/USD for chainlink
     * @custom:when Protocol action is InitiateDeposit
     * @custom:then The price retrieved by the oracle middleware is the same as the one from the chainlink on-chain data
     * by applying Steth/Wsteth on-chain price ratio
     */
    function test_ForkFFIParseAndValidatePriceForInitiateDepositWithChainlink() public ethMainnetFork reSetUp {
        // all targeted actions loop
        for (uint256 i; i < actions.length; i++) {
            // action type
            ProtocolAction action = actions[i];

            // if the action is only available for pyth, skip it
            if (
                action == ProtocolAction.None || action == ProtocolAction.ValidateDeposit
                    || action == ProtocolAction.ValidateWithdrawal || action == ProtocolAction.ValidateOpenPosition
                    || action == ProtocolAction.ValidateClosePosition || action == ProtocolAction.Liquidation
            ) {
                continue;
            }

            // timestamp error message
            string memory timestampError =
                string.concat("Wrong oracle middleware timestamp for action: ", uint256(action).toString());
            // price error message
            string memory priceError =
                string.concat("Wrong oracle middleware price for action: ", uint256(action).toString());

            // chainlink data
            (uint256 chainlinkPrice, uint256 chainlinkTimestamp) = getChainlinkPrice();
            // middleware data
            PriceInfo memory middlewarePrice =
                wstethMiddleware.parseAndValidatePrice("", uint128(block.timestamp), action, "");
            // timestamp check
            assertEq(middlewarePrice.timestamp, chainlinkTimestamp, timestampError);
            // price check
            assertEq(
                middlewarePrice.price,
                stethToWsteth(
                    chainlinkPrice * 10 ** wstethMiddleware.getDecimals()
                        / 10 ** wstethMiddleware.getChainlinkDecimals()
                ),
                priceError
            );
        }
    }

    // receive ether refunds
    receive() external payable { }
}

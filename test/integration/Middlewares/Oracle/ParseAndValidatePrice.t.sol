// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";

import { OracleMiddlewareBaseIntegrationFixture } from "test/integration/Middlewares/utils/Fixtures.sol";
import { PYTH_STETH_USD } from "test/utils/Constants.sol";

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
            (uint256 pythPrice, uint256 pythConf, uint256 pythDecimals, uint256 pythTimestamp, bytes memory data) =
                getMockedPythSignatureStETH();
            // Apply conf ratio to pyth confidence
            pythConf = (
                pythConf * 10 ** (oracleMiddleware.getDecimals() - pythDecimals) * oracleMiddleware.getConfRatioBps()
            ) / oracleMiddleware.BPS_DIVISOR();

            // middleware data
            PriceInfo memory middlewarePrice;
            uint256 validationCost = oracleMiddleware.validationCost(data, action);

            if (
                action == ProtocolAction.Initialize || action == ProtocolAction.Liquidation
                    || action == ProtocolAction.InitiateDeposit || action == ProtocolAction.InitiateWithdrawal
                    || action == ProtocolAction.InitiateOpenPosition || action == ProtocolAction.InitiateClosePosition
            ) {
                // Since we force the usage of Pyth for initiate actions, Pyth requires that the price data timestamp
                // is recent compared to block.timestamp
                vm.warp(pythTimestamp);
                middlewarePrice = oracleMiddleware.parseAndValidatePrice{ value: validationCost }(0, action, data);
            } else {
                middlewarePrice = oracleMiddleware.parseAndValidatePrice{ value: validationCost }(
                    uint128(pythTimestamp - oracleMiddleware.getValidationDelay()), action, data
                );
            }

            // timestamp check
            assertEq(middlewarePrice.timestamp, pythTimestamp);

            uint256 formattedPythPrice = pythPrice * 10 ** (oracleMiddleware.getDecimals() - pythDecimals);

            // Price + conf
            if (
                action == ProtocolAction.InitiateWithdrawal || action == ProtocolAction.ValidateWithdrawal
                    || action == ProtocolAction.InitiateOpenPosition || action == ProtocolAction.ValidateOpenPosition
            ) {
                assertEq(middlewarePrice.price, formattedPythPrice + pythConf, priceError);
            }
            // Price - conf
            else if (
                action == ProtocolAction.InitiateDeposit || action == ProtocolAction.ValidateDeposit
                    || action == ProtocolAction.InitiateClosePosition || action == ProtocolAction.ValidateClosePosition
            ) {
                assertEq(middlewarePrice.price, formattedPythPrice - pythConf, priceError);
            }
            // Price only
            else {
                // check price
                assertEq(middlewarePrice.price, formattedPythPrice, priceError);
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
            PriceInfo memory middlewarePrice = oracleMiddleware.parseAndValidatePrice(
                uint128(block.timestamp - oracleMiddleware.getValidationDelay()), action, ""
            );
            // timestamp check
            assertEq(middlewarePrice.timestamp, chainlinkTimestamp, timestampError);
            // price check
            assertEq(
                middlewarePrice.price * 10 ** oracleMiddleware.getChainlinkDecimals()
                    / 10 ** oracleMiddleware.getDecimals(),
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
     * @custom:and The validation delay is respected
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
            (uint256 pythPrice, uint256 pythConf, uint256 pythDecimals, uint256 pythTimestamp, bytes memory data) =
                getHermesApiSignature(PYTH_STETH_USD, block.timestamp);
            // Apply conf ratio to pyth confidence
            pythConf = (
                pythConf * 10 ** (oracleMiddleware.getDecimals() - pythDecimals) * oracleMiddleware.getConfRatioBps()
            ) / oracleMiddleware.BPS_DIVISOR();

            // middleware data
            PriceInfo memory middlewarePrice;
            uint256 validationCost = oracleMiddleware.validationCost(data, action);
            if (
                action == ProtocolAction.Initialize || action == ProtocolAction.Liquidation
                    || action == ProtocolAction.InitiateDeposit || action == ProtocolAction.InitiateWithdrawal
                    || action == ProtocolAction.InitiateOpenPosition || action == ProtocolAction.InitiateClosePosition
            ) {
                // Since we force the usage of Pyth for initiate actions, Pyth requires that the price data timestamp
                // is recent compared to block.timestamp
                vm.warp(pythTimestamp);
                middlewarePrice = oracleMiddleware.parseAndValidatePrice{ value: validationCost }(0, action, data);
            } else {
                middlewarePrice = oracleMiddleware.parseAndValidatePrice{ value: validationCost }(
                    uint128(pythTimestamp - oracleMiddleware.getValidationDelay()), action, data
                );
            }

            uint256 formattedPythPrice = pythPrice * 10 ** (oracleMiddleware.getDecimals() - pythDecimals);

            // timestamp check
            assertEq(middlewarePrice.timestamp, pythTimestamp);
            // Price + conf
            if (
                action == ProtocolAction.InitiateWithdrawal || action == ProtocolAction.ValidateWithdrawal
                    || action == ProtocolAction.InitiateOpenPosition || action == ProtocolAction.ValidateOpenPosition
            ) {
                assertEq(middlewarePrice.price, formattedPythPrice + pythConf, priceError);
            }
            // Price - conf
            else if (
                action == ProtocolAction.InitiateDeposit || action == ProtocolAction.ValidateDeposit
                    || action == ProtocolAction.InitiateClosePosition || action == ProtocolAction.ValidateClosePosition
            ) {
                assertEq(middlewarePrice.price, formattedPythPrice - pythConf, priceError);
            }
            // Price only
            else {
                // check price
                assertEq(middlewarePrice.price, formattedPythPrice, priceError);
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
            PriceInfo memory middlewarePrice = oracleMiddleware.parseAndValidatePrice(
                uint128(block.timestamp - oracleMiddleware.getValidationDelay()), action, ""
            );
            // timestamp check
            assertEq(middlewarePrice.timestamp, chainlinkTimestamp, timestampError);
            // price check
            assertEq(
                middlewarePrice.price * 10 ** oracleMiddleware.getChainlinkDecimals()
                    / 10 ** oracleMiddleware.getDecimals(),
                chainlinkPrice,
                priceError
            );
        }
    }

    /**
     * @custom:scenario Use cached Pyth value for initiate actions if possible
     * @custom:given A pyth signature was provided to the oracle more recently than the latest chainlink on-chain data
     * @custom:when A user retrieves a price for a `initiate` action without providing data
     * @custom:then The price retrieved by the oracle middleware is the one from pyth
     */
    function test_ForkFFIUseCachedPythPrice() public ethMainnetFork reSetUp {
        // chainlink data
        (uint256 chainlinkPrice, uint256 chainlinkTimestamp) = getChainlinkPrice();

        // get pyth price that must be more recent than chainlink data
        (,,,, bytes memory data) = getHermesApiSignature(PYTH_STETH_USD, chainlinkTimestamp + 1);
        uint256 validationCost = oracleMiddleware.validationCost(data, ProtocolAction.ValidateDeposit);

        // submit to oracle middleware so it gets cached by Pyth
        PriceInfo memory middlewarePrice = oracleMiddleware.parseAndValidatePrice{ value: validationCost }(
            uint128(chainlinkTimestamp + 1 - oracleMiddleware.getValidationDelay()),
            ProtocolAction.ValidateDeposit,
            data
        );

        // get oracle middleware price without providing data
        PriceInfo memory cachedMiddlewarePrice =
            oracleMiddleware.parseAndValidatePrice(uint128(block.timestamp), ProtocolAction.InitiateDeposit, "");

        // timestamp check
        assertEq(cachedMiddlewarePrice.timestamp, middlewarePrice.timestamp, "timestamp equal to pyth timestamp");
        assertGt(cachedMiddlewarePrice.timestamp, chainlinkTimestamp, "timestamp greater than chainlink timestamp");
        // price check
        assertEq(cachedMiddlewarePrice.price, middlewarePrice.price, "price equal to pyth price");
        assertTrue(cachedMiddlewarePrice.price != chainlinkPrice, "price different from chainlink price");
    }

    /**
     * @custom:scenario The cached Pyth price for initiate action is too old
     * @custom:given A pyth signature was provided to the oracle more recently than the last chainlink price
     * @custom:and The chainlink price is too old (there is a problem with chainlink)
     * @custom:when A user retrieves a price for a `initiate` action without providing data
     * @custom:then The price is retrieved from Pyth but checked for freshness and the tx reverts with
     * `OracleMiddlewarePriceTooOld`
     */
    function test_RevertWhen_ForkFFIOldCachedPythPrice() public ethMainnetFork reSetUp {
        // chainlink data
        (, uint256 chainlinkTimestamp) = getChainlinkPrice();

        // get pyth price that must be more recent than chainlink data
        (,,,, bytes memory data) = getHermesApiSignature(PYTH_STETH_USD, chainlinkTimestamp + 1);
        uint256 validationCost = oracleMiddleware.validationCost(data, ProtocolAction.ValidateDeposit);

        // submit to oracle middleware so it gets cached by Pyth
        oracleMiddleware.parseAndValidatePrice{ value: validationCost }(
            uint128(chainlinkTimestamp + 1 - oracleMiddleware.getValidationDelay()),
            ProtocolAction.ValidateDeposit,
            data
        );

        // wait for more than _timeElapsedLimit from the middleware
        skip(oracleMiddleware.getChainlinkTimeElapsedLimit() + 1);

        // get oracle middleware price without providing data
        vm.expectRevert(abi.encodeWithSelector(OracleMiddlewarePriceTooOld.selector, chainlinkTimestamp + 1));
        oracleMiddleware.parseAndValidatePrice(uint128(block.timestamp), ProtocolAction.InitiateDeposit, "");
    }

    // receive ether refunds
    receive() external payable { }
}

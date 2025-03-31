// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";
import { PythStructs } from "@pythnetwork/pyth-sdk-solidity/PythStructs.sol";
import { FixedPointMathLib } from "solady/src/utils/FixedPointMathLib.sol";

import { PYTH_ETH_USD } from "../../../utils/Constants.sol";
import { CHAINLINK_BLOCK_NUMBER, PYTH_PRICE_BLOCK_NUMBER } from "../utils/Constants.sol";
import { OracleMiddlewareBaseIntegrationFixture } from "../utils/Fixtures.sol";

import { PriceInfo } from "../../../../src/interfaces/OracleMiddleware/IOracleMiddlewareTypes.sol";

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
     * @custom:given The price feed is ETH/USD for pyth
     * @custom:and The validationDelay is respected
     * @custom:when The Protocol action is any targeted action
     * @custom:then The price signature is well-decoded
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
                getMockedPythSignatureETH();
            // apply conf ratio to pyth confidence
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
                // since we force the usage of Pyth for initiate actions, Pyth requires
                // that the price data timestamp is recent compared to block.timestamp
                vm.warp(pythTimestamp);
                middlewarePrice = oracleMiddleware.parseAndValidatePrice{ value: validationCost }("", 0, action, data);
            } else {
                middlewarePrice = oracleMiddleware.parseAndValidatePrice{ value: validationCost }(
                    "", uint128(pythTimestamp - oracleMiddleware.getValidationDelay()), action, data
                );
            }

            // timestamp check
            assertEq(middlewarePrice.timestamp, pythTimestamp);

            uint256 formattedPythPrice = pythPrice * 10 ** (oracleMiddleware.getDecimals() - pythDecimals);

            // price + conf
            if (action == ProtocolAction.ValidateWithdrawal || action == ProtocolAction.ValidateOpenPosition) {
                assertEq(middlewarePrice.price, formattedPythPrice + pythConf, priceError);
            }
            // price - conf
            else if (action == ProtocolAction.ValidateDeposit || action == ProtocolAction.ValidateClosePosition) {
                assertEq(middlewarePrice.price, formattedPythPrice - pythConf, priceError);
            }
            // price only
            else {
                // check price
                assertEq(middlewarePrice.price, formattedPythPrice, priceError);
            }
        }
    }

    /**
     * @custom:scenario Parse and validate price with chainlink on-chain
     * @custom:given The price feed is eth/usd for chainlink
     * @custom:when The protocol action is any targeted action
     * @custom:then The price retrieved by the oracle middleware is the same as the one from chainlink on-chain data
     */
    function test_ForkParseAndValidatePriceForAllInitiateActionsWithChainlink() public ethMainnetFork reSetUp {
        // roll to a block where the chainlink price is more recent than Pyth's unsafe one
        vm.rollFork(CHAINLINK_BLOCK_NUMBER);

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
            string memory timestampError = string.concat("Wrong oracle middleware timestamp for ", actionNames[i]);
            // price error message
            string memory priceError = string.concat("Wrong oracle middleware price for ", actionNames[i]);

            // chainlink data
            (uint256 chainlinkPrice, uint256 chainlinkTimestamp) = getChainlinkPrice();
            // middleware data
            PriceInfo memory middlewarePrice = oracleMiddleware.parseAndValidatePrice(
                "", uint128(block.timestamp - oracleMiddleware.getValidationDelay()), action, ""
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
     * @custom:scenario Parse and validate price with Pyth's unsafe price
     * @custom:given The price feed is ETH/USD for chainlink
     * @custom:and The unsafe Pyth's price is more recent
     * @custom:when The Protocol action is any InitiateDeposit
     * @custom:then The price retrieved by the oracle middleware is the same as the one from the Pyth on-chain cache
     * by applying Steth/Wsteth on-chain price ratio
     */
    function test_ForkEthParseAndValidatePriceForInitiateDepositWithUnsafePyth() public ethMainnetFork reSetUp {
        // roll to a block where the chainlink price is older than Pyth's unsafe one
        vm.rollFork(PYTH_PRICE_BLOCK_NUMBER);

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

            // pyth data
            PythStructs.Price memory pythPrice = getPythUnsafePrice();
            uint256 price = uint64(pythPrice.price);
            price *= 10 ** oracleMiddleware.getDecimals() / 10 ** uint32(-pythPrice.expo);

            // middleware data
            PriceInfo memory middlewarePrice =
                oracleMiddleware.parseAndValidatePrice("", uint128(block.timestamp), action, "");

            // timestamp check
            assertEq(middlewarePrice.timestamp, pythPrice.publishTime, timestampError);
            // price check
            assertEq(middlewarePrice.price, price, priceError);
        }
    }

    /* -------------------------------------------------------------------------- */
    /*                                  With FFI                                  */
    /* -------------------------------------------------------------------------- */

    /**
     * @custom:scenario Parse and validate price with mocked hermes API signature for pyth
     * @custom:given The price feed is ETH/USD for pyth
     * @custom:and The validation delay is respected
     * @custom:when The Protocol action is any targeted action
     * @custom:then The price signature is well-decoded
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
                getHermesApiSignature(PYTH_ETH_USD, block.timestamp);
            // apply conf ratio to pyth confidence
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
                // since we force the usage of Pyth for initiate actions, Pyth requires
                // that the price data timestamp is recent compared to block.timestamp
                vm.warp(pythTimestamp);
                middlewarePrice = oracleMiddleware.parseAndValidatePrice{ value: validationCost }("", 0, action, data);
            } else {
                middlewarePrice = oracleMiddleware.parseAndValidatePrice{ value: validationCost }(
                    "", uint128(pythTimestamp - oracleMiddleware.getValidationDelay()), action, data
                );
            }

            uint256 formattedPythPrice = pythPrice * 10 ** (oracleMiddleware.getDecimals() - pythDecimals);

            // timestamp check
            assertEq(middlewarePrice.timestamp, pythTimestamp);
            // price + conf
            if (action == ProtocolAction.ValidateWithdrawal || action == ProtocolAction.ValidateOpenPosition) {
                assertEq(middlewarePrice.price, formattedPythPrice + pythConf, priceError);
            }
            // price - conf
            else if (action == ProtocolAction.ValidateDeposit || action == ProtocolAction.ValidateClosePosition) {
                assertEq(middlewarePrice.price, formattedPythPrice - pythConf, priceError);
            }
            // price only
            else {
                // check price
                assertEq(middlewarePrice.price, formattedPythPrice, priceError);
            }
        }
    }

    /**
     * @custom:scenario Parse and validate price with chainlink on-chain
     * @custom:given The price feed is eth/usd for chainlink
     * @custom:when Protocol action is an `initiateDeposit`
     * @custom:then The price signature is well-decoded
     * @custom:and The price retrieved by the oracle middleware is the same as the one from the chainlink on-chain data
     */
    function test_ForkFFIParseAndValidatePriceForAllInitiateActionsWithChainlink() public ethMainnetFork reSetUp {
        // roll to a block where the chainlink price is more recent than Pyth's unsafe one
        vm.rollFork(CHAINLINK_BLOCK_NUMBER);

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
            string memory timestampError = string.concat("Wrong oracle middleware timestamp for ", actionNames[i]);
            // price error message
            string memory priceError = string.concat("Wrong oracle middleware price for ", actionNames[i]);

            // chainlink data
            (uint256 chainlinkPrice, uint256 chainlinkTimestamp) = getChainlinkPrice();
            // middleware data
            PriceInfo memory middlewarePrice = oracleMiddleware.parseAndValidatePrice(
                "", uint128(block.timestamp - oracleMiddleware.getValidationDelay()), action, ""
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
     * @custom:scenario Uses the cached Pyth value for `initiate` actions.
     * @custom:given A pyth signature was provided to the oracle more recently than the last chainlink price.
     * @custom:when A user retrieves a price for a `initiate` action without providing data.
     * @custom:then The price retrieved by the oracle middleware must be equal to the unsafe Pyth price.
     */
    function test_ForkFFIUseCachedPythPrice() public ethMainnetFork reSetUp {
        vm.rollFork(PYTH_PRICE_BLOCK_NUMBER);
        (uint256 chainlinkPrice, uint256 chainlinkTimestamp) = getChainlinkPrice();

        PythStructs.Price memory unsafePythPrice = getPythUnsafePrice();

        uint256 adjustedUnsafePythPrice = uint256(
            uint64(unsafePythPrice.price)
                * 10 ** (oracleMiddleware.getDecimals() - FixedPointMathLib.abs(unsafePythPrice.expo))
        );

        // get oracle middleware price without providing data
        PriceInfo memory middlewarePrice =
            oracleMiddleware.parseAndValidatePrice("", uint128(block.timestamp), ProtocolAction.InitiateDeposit, "");

        // timestamp check
        assertEq(middlewarePrice.timestamp, unsafePythPrice.publishTime, "timestamp equal to pyth unsafe timestamp");
        assertGt(middlewarePrice.timestamp, chainlinkTimestamp, "timestamp greater than chainlink timestamp");
        // price check
        assertEq(middlewarePrice.neutralPrice, adjustedUnsafePythPrice, "price equal to pyth price");
        assertTrue(middlewarePrice.neutralPrice != chainlinkPrice, "price different from chainlink price");
    }

    /**
     * @custom:scenario The cached Pyth price for initiate action is too old.
     * @custom:given A pyth signature was provided to the oracle more recently than the last chainlink price.
     * @custom:and The chainlink price is too old (there is a problem with chainlink).
     * @custom:when A user retrieves a price for a `initiate` action without providing data.
     * @custom:then The price is retrieved from Pyth but checked for freshness and the transaction reverts with
     * `OracleMiddlewarePriceTooOld`.
     */
    function test_RevertWhen_ForkFFIOldCachedPythPrice() public ethMainnetFork reSetUp {
        vm.rollFork(PYTH_PRICE_BLOCK_NUMBER);
        skip(oracleMiddleware.getChainlinkTimeElapsedLimit());

        PythStructs.Price memory unsafePythPrice = getPythUnsafePrice();

        // get oracle middleware price without providing data
        vm.expectRevert(
            abi.encodeWithSelector(OracleMiddlewarePriceTooOld.selector, uint64(unsafePythPrice.publishTime))
        );
        oracleMiddleware.parseAndValidatePrice("", uint128(block.timestamp), ProtocolAction.InitiateDeposit, "");
    }

    // receive ether refunds
    receive() external payable { }
}

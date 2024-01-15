// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { console2 } from "forge-std/Test.sol";

import { OracleMiddlewareBaseFixture } from "test/unit/OracleMiddleware/utils/Fixtures.sol";
import { ETH_PRICE, ETH_CONF } from "test/unit/OracleMiddleware/utils/Constants.sol";

import { PriceInfo, ProtocolAction } from "src/interfaces/IOracleMiddleware.sol";

/**
 * @custom:feature The `parseAndValidatePrice` function of `OracleMiddleware`
 * @custom:background Given the price of ETH is 2000 USD
 * @custom:and The confidence interval is 20 USD
 */
contract TestOracleMiddlewareGetPrice is OracleMiddlewareBaseFixture {
    uint256 immutable FORMATTED_ETH_PRICE;
    uint256 immutable FORMATTED_ETH_CONF;

    constructor() {
        super.setUp();

        FORMATTED_ETH_PRICE = ETH_PRICE * (10 ** oracleMiddleware.decimals()) / (10 ** oracleMiddleware.pythDecimals());
        FORMATTED_ETH_CONF = ETH_CONF * (10 ** oracleMiddleware.decimals()) / (10 ** oracleMiddleware.pythDecimals());
    }

    function setUp() public override {
        super.setUp();
    }

    /**
     * @custom:scenario Parse and validate price
     * @custom:given ETH price is 2000 USD in pyth and chainlink oracles
     * @custom:and The validationDelay is respected
     * @custom:when Protocol action is "None"
     * @custom:then The price is exactly 2000 USD
     */
    function test_parseAndValidatePriceForNoneAction() public {
        PriceInfo memory price = oracleMiddleware.parseAndValidatePrice(
            uint128(block.timestamp - oracleMiddleware.validationDelay()), ProtocolAction.None, abi.encode("data")
        );
        assertEq(price.price, FORMATTED_ETH_PRICE, "Wrong price for None action");
    }

    /**
     * @custom:scenario Parse and validate price
     * @custom:given ETH price is 2000 USD in pyth and chainlink oracles
     * @custom:and The validationDelay is respected
     * @custom:when Protocol action is "Initialize"
     * @custom:then The price is exactly 2000 USD
     */
    function test_parseAndValidatePriceForInitializeAction() public {
        PriceInfo memory price = oracleMiddleware.parseAndValidatePrice(
            uint128(block.timestamp - oracleMiddleware.validationDelay()), ProtocolAction.Initialize, abi.encode("data")
        );
        assertEq(price.price, FORMATTED_ETH_PRICE, "Wrong price for Initialize action");
    }

    /**
     * @custom:scenario Parse and validate price
     * @custom:given ETH price is 2000 USD in pyth and chainlink oracles
     * @custom:and The validationDelay is respected
     * @custom:when Protocol action is "InitiateDeposit"
     * @custom:then The price is exactly 2000 USD
     */
    function test_parseAndValidatePriceForInitiateDepositAction() public {
        PriceInfo memory price = oracleMiddleware.parseAndValidatePrice(
            uint128(block.timestamp - oracleMiddleware.validationDelay()),
            ProtocolAction.InitiateDeposit,
            abi.encode("data")
        );
        assertEq(price.price, FORMATTED_ETH_PRICE, "Wrong price for InitiateDeposit action");
    }

    /**
     * @custom:scenario Parse and validate price
     * @custom:given ETH price is 2000 USD in pyth and chainlink oracles
     * @custom:and The validationDelay is respected
     * @custom:when Protocol action is "ValidateDeposit"
     * @custom:then The price is 2000 USD (ETH price) - 20 USD (pyth confidence interval)
     */
    function test_parseAndValidatePriceForValidateDepositAction() public {
        PriceInfo memory price = oracleMiddleware.parseAndValidatePrice(
            uint128(block.timestamp - oracleMiddleware.validationDelay()),
            ProtocolAction.ValidateDeposit,
            abi.encode("data")
        );
        assertEq(price.price, FORMATTED_ETH_PRICE - FORMATTED_ETH_CONF, "Wrong price for ValidateDeposit action");
    }

    /**
     * @custom:scenario Parse and validate price
     * @custom:given ETH price is 2000 USD in pyth and chainlink oracles
     * @custom:and The validationDelay is respected
     * @custom:when Protocol action is "InitiateWithdrawal"
     * @custom:then The price is exactly 2000 USD
     */
    function test_parseAndValidatePriceForInitiateWithdrawalAction() public {
        PriceInfo memory price = oracleMiddleware.parseAndValidatePrice(
            uint128(block.timestamp - oracleMiddleware.validationDelay()),
            ProtocolAction.InitiateWithdrawal,
            abi.encode("data")
        );
        assertEq(price.price, FORMATTED_ETH_PRICE, "Wrong price for InitiateWithdrawal action");
    }

    /**
     * @custom:scenario Parse and validate price
     * @custom:given ETH price is 2000 USD in pyth and chainlink oracles
     * @custom:and The validationDelay is respected
     * @custom:when Protocol action is "ValidateWithdrawal"
     * @custom:then The price is exactly 2000 USD
     */
    function test_parseAndValidatePriceForValidateWithdrawalAction() public {
        PriceInfo memory price = oracleMiddleware.parseAndValidatePrice(
            uint128(block.timestamp - oracleMiddleware.validationDelay()),
            ProtocolAction.ValidateWithdrawal,
            abi.encode("data")
        );
        assertEq(price.price, FORMATTED_ETH_PRICE, "Wrong price for ValidateWithdrawal action");
    }

    /**
     * @custom:scenario Parse and validate price
     * @custom:given ETH price is 2000 USD in pyth and chainlink oracles
     * @custom:and The validationDelay is respected
     * @custom:when Protocol action is "InitiateOpenPosition"
     * @custom:then The price is exactly 2000 USD
     */
    function test_parseAndValidatePriceForInitiateOpenPositionAction() public {
        PriceInfo memory price = oracleMiddleware.parseAndValidatePrice(
            uint128(block.timestamp - oracleMiddleware.validationDelay()),
            ProtocolAction.InitiateOpenPosition,
            abi.encode("data")
        );
        assertEq(price.price, FORMATTED_ETH_PRICE, "Wrong price for InitiateOpenPosition action");
    }

    /**
     * @custom:scenario Parse and validate price
     * @custom:given ETH price is 2000 USD in pyth and chainlink oracles
     * @custom:and The validationDelay is respected
     * @custom:when Protocol action is "ValidateOpenPosition"
     * @custom:then The price is 2000 USD (ETH price) + 20 USD (pyth confidence interval)
     */
    function test_parseAndValidatePriceForValidateOpenPositionAction() public {
        PriceInfo memory price = oracleMiddleware.parseAndValidatePrice(
            uint128(block.timestamp - oracleMiddleware.validationDelay()),
            ProtocolAction.ValidateOpenPosition,
            abi.encode("data")
        );
        assertEq(price.price, FORMATTED_ETH_PRICE + FORMATTED_ETH_CONF, "Wrong price for ValidateOpenPosition action");
    }

    /**
     * @custom:scenario Parse and validate price
     * @custom:given ETH price is 2000 USD in pyth and chainlink oracles
     * @custom:and The validationDelay is respected
     * @custom:when Protocol action is "InitiateClosePosition"
     * @custom:then The price is exactly 2000 USD
     */
    function test_parseAndValidatePriceForInitiateClosePositionAction() public {
        PriceInfo memory price = oracleMiddleware.parseAndValidatePrice(
            uint128(block.timestamp - oracleMiddleware.validationDelay()),
            ProtocolAction.InitiateClosePosition,
            abi.encode("data")
        );
        assertEq(price.price, FORMATTED_ETH_PRICE, "Wrong price for InitiateClosePosition action");
    }

    /**
     * @custom:scenario Parse and validate price
     * @custom:given ETH price is 2000 USD in pyth and chainlink oracles
     * @custom:and The validationDelay is respected
     * @custom:when Protocol action is "ValidateClosePosition"
     * @custom:then The price is 2000 USD (ETH price) - 20 USD (pyth confidence interval)
     */
    function test_parseAndValidatePriceForValidateClosePositionAction() public {
        PriceInfo memory price = oracleMiddleware.parseAndValidatePrice(
            uint128(block.timestamp - oracleMiddleware.validationDelay()),
            ProtocolAction.ValidateClosePosition,
            abi.encode("data")
        );
        assertEq(price.price, FORMATTED_ETH_PRICE - FORMATTED_ETH_CONF, "Wrong price for ValidateClosePosition action");
    }

    /**
     * @custom:scenario Parse and validate price
     * @custom:given ETH price is 2000 USD in pyth and chainlink oracles
     * @custom:and The validationDelay is respected
     * @custom:when Protocol action is "Liquidation"
     * @custom:then The price is 2000 USD (ETH price) - 20 USD (pyth confidence interval)
     */
    function test_parseAndValidatePriceForLiquidationAction() public {
        PriceInfo memory price = oracleMiddleware.parseAndValidatePrice(
            uint128(block.timestamp - oracleMiddleware.validationDelay()),
            ProtocolAction.Liquidation,
            abi.encode("data")
        );
        assertEq(price.price, FORMATTED_ETH_PRICE - FORMATTED_ETH_CONF, "Wrong price for Liquidation action");
    }
}

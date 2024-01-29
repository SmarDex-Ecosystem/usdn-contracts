// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { console2 } from "forge-std/Test.sol";

import { WstethBaseFixture } from "test/unit/OracleMiddleware/utils/WstethOracleFixtures.sol";
import { ETH_PRICE, ETH_CONF } from "test/unit/OracleMiddleware/utils/Constants.sol";

import { IOracleMiddlewareErrors, PriceInfo, ProtocolAction } from "src/interfaces/IOracleMiddleware.sol";

/**
 * @custom:feature The `parseAndValidatePrice` function of `WstethOracle`
 * @custom:background Given the price WSTETH is ~1739 USD
 * @custom:and The confidence interval is 20 USD
 */
contract TestWstethOracleParseAndValidatePrice is WstethBaseFixture, IOracleMiddlewareErrors {
    uint256 immutable FORMATTED_WSTETH_PRICE;
    uint256 immutable FORMATTED_WSTETH_CONF;

    constructor() {
        super.setUp();

        uint256 formattedStEthPrice =
            (ETH_PRICE * (10 ** wstethOracle.decimals())) / (10 ** wstethOracle.pythDecimals());
        uint256 formattedStEthConf = (ETH_CONF * (10 ** wstethOracle.decimals())) / (10 ** wstethOracle.pythDecimals());
        uint256 stEthPerToken = wsteth.stEthPerToken();
        FORMATTED_WSTETH_PRICE = formattedStEthPrice * 1 ether / stEthPerToken;
        FORMATTED_WSTETH_CONF = formattedStEthConf * 1 ether / stEthPerToken;
    }

    function setUp() public override {
        super.setUp();
    }

    /* -------------------------------------------------------------------------- */
    /*                               WSTETH is ~1739 USD                              */
    /* -------------------------------------------------------------------------- */

    /**
     * @custom:scenario Parse and validate price
     * @custom:given WSTETH price is ~1739 USD in pyth and chainlink oracles
     * @custom:and The validationDelay is respected
     * @custom:when Protocol action is "None"
     * @custom:then The price is exactly ~1739 USD
     */
    function test_parseAndValidatePriceForNoneAction() public {
        PriceInfo memory price = wstethOracle.parseAndValidatePrice(
            uint128(block.timestamp - wstethOracle.validationDelay()), ProtocolAction.None, abi.encode("data")
        );
        assertEq(price.price, FORMATTED_WSTETH_PRICE, "Wrong price for None action");
    }

    /**
     * @custom:scenario Parse and validate price
     * @custom:given WSTETH price is ~1739 USD in pyth and chainlink oracles
     * @custom:and The validationDelay is respected
     * @custom:when Protocol action is "Initialize"
     * @custom:then The price is ~1739 USD
     */
    function test_parseAndValidatePriceForInitializeAction() public {
        PriceInfo memory price = wstethOracle.parseAndValidatePrice(
            uint128(block.timestamp - wstethOracle.validationDelay()), ProtocolAction.Initialize, abi.encode("data")
        );
        assertEq(price.price, FORMATTED_WSTETH_PRICE, "Wrong price for Initialize action");
    }

    /**
     * @custom:scenario Parse and validate price
     * @custom:given WSTETH price is ~1739 USD in pyth and chainlink oracles
     * @custom:and The validationDelay is respected
     * @custom:when Protocol action is "InitiateDeposit"
     * @custom:then The price is ~1739 USD
     */
    function test_parseAndValidatePriceForInitiateDepositAction() public {
        PriceInfo memory price = wstethOracle.parseAndValidatePrice(
            uint128(block.timestamp - wstethOracle.validationDelay()),
            ProtocolAction.InitiateDeposit,
            abi.encode("data")
        );
        assertEq(price.price, FORMATTED_WSTETH_PRICE, "Wrong price for InitiateDeposit action");
    }

    /**
     * @custom:scenario Parse and validate price
     * @custom:given WSTETH price is ~1739 USD in pyth and chainlink oracles
     * @custom:and The validationDelay is respected
     * @custom:when Protocol action is "ValidateDeposit"
     * @custom:then The price is ~1739 USD (WSTETH price) - 20 USD (pyth confidence interval)
     */
    function test_parseAndValidatePriceForValidateDepositAction() public {
        PriceInfo memory price = wstethOracle.parseAndValidatePrice(
            uint128(block.timestamp - wstethOracle.validationDelay()),
            ProtocolAction.ValidateDeposit,
            abi.encode("data")
        );
        assertApproxEqAbs(
            price.price, FORMATTED_WSTETH_PRICE - FORMATTED_WSTETH_CONF, 1, "Wrong price for ValidateDeposit action"
        );
    }

    /**
     * @custom:scenario Parse and validate price
     * @custom:given WSTETH price is ~1739 USD in pyth and chainlink oracles
     * @custom:and The validationDelay is respected
     * @custom:when Protocol action is "InitiateWithdrawal"
     * @custom:then The price is ~1739 USD
     */
    function test_parseAndValidatePriceForInitiateWithdrawalAction() public {
        PriceInfo memory price = wstethOracle.parseAndValidatePrice(
            uint128(block.timestamp - wstethOracle.validationDelay()),
            ProtocolAction.InitiateWithdrawal,
            abi.encode("data")
        );
        assertEq(price.price, FORMATTED_WSTETH_PRICE, "Wrong price for InitiateWithdrawal action");
    }

    /**
     * @custom:scenario Parse and validate price
     * @custom:given WSTETH price is ~1739 USD in pyth and chainlink oracles
     * @custom:and The validationDelay is respected
     * @custom:when Protocol action is "ValidateWithdrawal"
     * @custom:then The price is ~1739 USD
     */
    function test_parseAndValidatePriceForValidateWithdrawalAction() public {
        PriceInfo memory price = wstethOracle.parseAndValidatePrice(
            uint128(block.timestamp - wstethOracle.validationDelay()),
            ProtocolAction.ValidateWithdrawal,
            abi.encode("data")
        );
        assertEq(price.price, FORMATTED_WSTETH_PRICE, "Wrong price for ValidateWithdrawal action");
    }

    /**
     * @custom:scenario Parse and validate price
     * @custom:given WSTETH price is ~1739 USD in pyth and chainlink oracles
     * @custom:and The validationDelay is respected
     * @custom:when Protocol action is "InitiateOpenPosition"
     * @custom:then The price is ~1739 USD
     */
    function test_parseAndValidatePriceForInitiateOpenPositionAction() public {
        PriceInfo memory price = wstethOracle.parseAndValidatePrice{ value: 7777 }(
            uint128(block.timestamp - wstethOracle.validationDelay()),
            ProtocolAction.InitiateOpenPosition,
            abi.encode("data")
        );
        assertEq(price.price, FORMATTED_WSTETH_PRICE, "Wrong price for InitiateOpenPosition action");
    }

    /**
     * @custom:scenario Parse and validate price
     * @custom:given WSTETH price is ~1739 USD in pyth and chainlink oracles
     * @custom:and The validationDelay is respected
     * @custom:when Protocol action is "ValidateOpenPosition"
     * @custom:then The price is ~1739 USD (WSTETH price) + 20 USD (pyth confidence interval)
     */
    function test_parseAndValidatePriceForValidateOpenPositionAction() public {
        PriceInfo memory price = wstethOracle.parseAndValidatePrice(
            uint128(block.timestamp - wstethOracle.validationDelay()),
            ProtocolAction.ValidateOpenPosition,
            abi.encode("data")
        );
        assertEq(
            price.price, FORMATTED_WSTETH_PRICE + FORMATTED_WSTETH_CONF, "Wrong price for ValidateOpenPosition action"
        );
    }

    /**
     * @custom:scenario Parse and validate price
     * @custom:given WSTETH price is ~1739 USD in pyth and chainlink oracles
     * @custom:and The validationDelay is respected
     * @custom:when Protocol action is "InitiateClosePosition"
     * @custom:then The price is ~1739 USD
     */
    function test_parseAndValidatePriceForInitiateClosePositionAction() public {
        PriceInfo memory price = wstethOracle.parseAndValidatePrice(
            uint128(block.timestamp - wstethOracle.validationDelay()),
            ProtocolAction.InitiateClosePosition,
            abi.encode("data")
        );
        assertEq(price.price, FORMATTED_WSTETH_PRICE, "Wrong price for InitiateClosePosition action");
    }

    /**
     * @custom:scenario Parse and validate price
     * @custom:given WSTETH price is ~1739 USD in pyth and chainlink oracles
     * @custom:and The validationDelay is respected
     * @custom:when Protocol action is "ValidateClosePosition"
     * @custom:then The price is ~1739 USD (WSTETH price) - 20 USD (pyth confidence interval)
     */
    function test_parseAndValidatePriceForValidateClosePositionAction() public {
        PriceInfo memory price = wstethOracle.parseAndValidatePrice(
            uint128(block.timestamp - wstethOracle.validationDelay()),
            ProtocolAction.ValidateClosePosition,
            abi.encode("data")
        );
        assertApproxEqAbs(
            price.price,
            FORMATTED_WSTETH_PRICE - FORMATTED_WSTETH_CONF,
            1,
            "Wrong price for ValidateClosePosition action"
        );
    }

    /**
     * @custom:scenario Parse and validate price
     * @custom:given WSTETH price is ~1739 USD in pyth and chainlink oracles
     * @custom:and The validationDelay is respected
     * @custom:when Protocol action is "Liquidation"
     * @custom:then The price is ~1739 USD (WSTETH price) - 20 USD (pyth confidence interval)
     */
    function test_parseAndValidatePriceForLiquidationAction() public {
        PriceInfo memory price = wstethOracle.parseAndValidatePrice(
            uint128(block.timestamp - wstethOracle.validationDelay()), ProtocolAction.Liquidation, abi.encode("data")
        );
        assertApproxEqAbs(
            price.price, FORMATTED_WSTETH_PRICE - FORMATTED_WSTETH_CONF, 1, "Wrong price for Liquidation action"
        );
    }
}

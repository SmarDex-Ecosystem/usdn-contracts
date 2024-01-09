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

    function test_getPriceForNoneAction() public {
        PriceInfo memory price = oracleMiddleware.parseAndValidatePrice(
            uint128(block.timestamp - oracleMiddleware.validationDelay()), ProtocolAction.None, abi.encode("data")
        );
        assertEq(price.price, FORMATTED_ETH_PRICE, "Wrong price for None action");
    }

    function test_getPriceForInitializeAction() public {
        PriceInfo memory price = oracleMiddleware.parseAndValidatePrice(
            uint128(block.timestamp - oracleMiddleware.validationDelay()), ProtocolAction.Initialize, abi.encode("data")
        );
        assertEq(price.price, FORMATTED_ETH_PRICE, "Wrong price for Initialize action");
    }

    function test_getPriceForInitiateDepositAction() public {
        PriceInfo memory price = oracleMiddleware.parseAndValidatePrice(
            uint128(block.timestamp - oracleMiddleware.validationDelay()),
            ProtocolAction.InitiateDeposit,
            abi.encode("data")
        );
        assertEq(price.price, FORMATTED_ETH_PRICE, "Wrong price for InitiateDeposit action");
    }

    function test_getPriceForValidateDepositAction() public {
        PriceInfo memory price = oracleMiddleware.parseAndValidatePrice(
            uint128(block.timestamp - oracleMiddleware.validationDelay()),
            ProtocolAction.ValidateDeposit,
            abi.encode("data")
        );
        assertEq(price.price, FORMATTED_ETH_PRICE - FORMATTED_ETH_CONF, "Wrong price for ValidateDeposit action");
    }

    function test_getPriceForInitiateWithdrawalAction() public {
        PriceInfo memory price = oracleMiddleware.parseAndValidatePrice(
            uint128(block.timestamp - oracleMiddleware.validationDelay()),
            ProtocolAction.InitiateWithdrawal,
            abi.encode("data")
        );
        assertEq(price.price, FORMATTED_ETH_PRICE, "Wrong price for InitiateWithdrawal action");
    }

    function test_getPriceForValidateWithdrawalAction() public {
        PriceInfo memory price = oracleMiddleware.parseAndValidatePrice(
            uint128(block.timestamp - oracleMiddleware.validationDelay()),
            ProtocolAction.ValidateWithdrawal,
            abi.encode("data")
        );
        assertEq(price.price, FORMATTED_ETH_PRICE, "Wrong price for ValidateWithdrawal action");
    }

    function test_getPriceForInitiateOpenPositionAction() public {
        PriceInfo memory price = oracleMiddleware.parseAndValidatePrice(
            uint128(block.timestamp - oracleMiddleware.validationDelay()),
            ProtocolAction.InitiateOpenPosition,
            abi.encode("data")
        );
        assertEq(price.price, FORMATTED_ETH_PRICE, "Wrong price for InitiateOpenPosition action");
    }

    function test_getPriceForValidateOpenPositionAction() public {
        PriceInfo memory price = oracleMiddleware.parseAndValidatePrice(
            uint128(block.timestamp - oracleMiddleware.validationDelay()),
            ProtocolAction.ValidateOpenPosition,
            abi.encode("data")
        );
        assertEq(price.price, FORMATTED_ETH_PRICE + FORMATTED_ETH_CONF, "Wrong price for ValidateOpenPosition action");
    }

    function test_getPriceForInitiateClosePositionAction() public {
        PriceInfo memory price = oracleMiddleware.parseAndValidatePrice(
            uint128(block.timestamp - oracleMiddleware.validationDelay()),
            ProtocolAction.InitiateClosePosition,
            abi.encode("data")
        );
        assertEq(price.price, FORMATTED_ETH_PRICE, "Wrong price for InitiateClosePosition action");
    }

    function test_getPriceForValidateClosePositionAction() public {
        PriceInfo memory price = oracleMiddleware.parseAndValidatePrice(
            uint128(block.timestamp - oracleMiddleware.validationDelay()),
            ProtocolAction.ValidateClosePosition,
            abi.encode("data")
        );
        assertEq(price.price, FORMATTED_ETH_PRICE - FORMATTED_ETH_CONF, "Wrong price for ValidateClosePosition action");
    }

    function test_getPriceForLiquidationAction() public {
        PriceInfo memory price = oracleMiddleware.parseAndValidatePrice(
            uint128(block.timestamp - oracleMiddleware.validationDelay()),
            ProtocolAction.Liquidation,
            abi.encode("data")
        );
        assertEq(price.price, FORMATTED_ETH_PRICE - FORMATTED_ETH_CONF, "Wrong price for Liquidation action");
    }
}

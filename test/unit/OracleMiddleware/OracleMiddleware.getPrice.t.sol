// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { console2 } from "forge-std/Test.sol";

import { OracleMiddlewareBaseFixture } from "test/unit/OracleMiddleware/utils/Fixtures.sol";
import { ETH_PRICE, ETH_CONF } from "test/unit/OracleMiddleware/utils/Constants.sol";

import { PriceInfo, ProtocolAction } from "src/interfaces/IOracleMiddleware.sol";

contract TestOracleMiddlewareGetPrice is OracleMiddlewareBaseFixture {
    function setUp() public override {
        super.setUp();
    }

    function test_getPriceForNoneAction() public {
        PriceInfo memory price = oracleMiddleware.parseAndValidatePrice(
            uint128(block.timestamp - 24 seconds), ProtocolAction.None, abi.encode("data")
        );
        assertEq(price.price, ETH_PRICE, "Wrong price for None action");
    }

    function test_getPriceForInitializeAction() public {
        PriceInfo memory price = oracleMiddleware.parseAndValidatePrice(
            uint128(block.timestamp - 24 seconds), ProtocolAction.Initialize, abi.encode("data")
        );
        assertEq(price.price, ETH_PRICE, "Wrong price for Initialize action");
    }

    function test_getPriceForInitiateDepositAction() public {
        PriceInfo memory price = oracleMiddleware.parseAndValidatePrice(
            uint128(block.timestamp - 24 seconds), ProtocolAction.InitiateDeposit, abi.encode("data")
        );
        assertEq(price.price, ETH_PRICE, "Wrong price for InitiateDeposit action");
    }

    function test_getPriceForValidateDepositAction() public {
        PriceInfo memory price = oracleMiddleware.parseAndValidatePrice(
            uint128(block.timestamp - 24 seconds), ProtocolAction.ValidateDeposit, abi.encode("data")
        );
        assertEq(price.price, ETH_PRICE - ETH_CONF, "Wrong price for ValidateDeposit action");
    }

    function test_getPriceForInitiateWithdrawalAction() public {
        PriceInfo memory price = oracleMiddleware.parseAndValidatePrice(
            uint128(block.timestamp - 24 seconds), ProtocolAction.InitiateWithdrawal, abi.encode("data")
        );
        assertEq(price.price, ETH_PRICE, "Wrong price for InitiateWithdrawal action");
    }

    function test_getPriceForValidateWithdrawalAction() public {
        PriceInfo memory price = oracleMiddleware.parseAndValidatePrice(
            uint128(block.timestamp - 24 seconds), ProtocolAction.ValidateWithdrawal, abi.encode("data")
        );
        assertEq(price.price, ETH_PRICE - ETH_CONF, "Wrong price for ValidateWithdrawal action");
    }

    function test_getPriceForInitiateOpenPositionAction() public {
        PriceInfo memory price = oracleMiddleware.parseAndValidatePrice(
            uint128(block.timestamp - 24 seconds), ProtocolAction.InitiateOpenPosition, abi.encode("data")
        );
        assertEq(price.price, ETH_PRICE, "Wrong price for InitiateOpenPosition action");
    }

    function test_getPriceForValidateOpenPositionAction() public {
        PriceInfo memory price = oracleMiddleware.parseAndValidatePrice(
            uint128(block.timestamp - 24 seconds), ProtocolAction.ValidateOpenPosition, abi.encode("data")
        );
        assertEq(price.price, ETH_PRICE + ETH_CONF, "Wrong price for ValidateOpenPosition action");
    }

    function test_getPriceForInitiateClosePositionAction() public {
        PriceInfo memory price = oracleMiddleware.parseAndValidatePrice(
            uint128(block.timestamp - 24 seconds), ProtocolAction.InitiateClosePosition, abi.encode("data")
        );
        assertEq(price.price, ETH_PRICE, "Wrong price for InitiateClosePosition action");
    }

    function test_getPriceForValidateClosePositionAction() public {
        PriceInfo memory price = oracleMiddleware.parseAndValidatePrice(
            uint128(block.timestamp - 24 seconds), ProtocolAction.ValidateClosePosition, abi.encode("data")
        );
        assertEq(price.price, ETH_PRICE - ETH_CONF, "Wrong price for ValidateClosePosition action");
    }

    function test_getPriceForLiquidationAction() public {
        PriceInfo memory price = oracleMiddleware.parseAndValidatePrice(
            uint128(block.timestamp - 24 seconds), ProtocolAction.Liquidation, abi.encode("data")
        );
        assertEq(price.price, ETH_PRICE - ETH_CONF, "Wrong price for Liquidation action");
    }
}

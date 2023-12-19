// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { console2 } from "forge-std/Test.sol";

import { OracleMiddlewareBaseFixture } from "test/unit/OracleMiddleware/utils/Fixtures.sol";

import { PriceInfo, ProtocolAction } from "src/interfaces/IOracleMiddleware.sol";

contract TestOracleMiddlewareGetPrice is OracleMiddlewareBaseFixture {
    function setUp() public override {
        super.setUp();
    }

    function test_getPriceForNoneAction() public {
        PriceInfo memory price = oracleMiddleware.parseAndValidatePrice(
            uint128(block.timestamp - 24 seconds), ProtocolAction.None, abi.encode("someDateToValidate")
        );

        assertEq(price.price, 2000 gwei, "Price should be 2000 gwei");
    }

    function test_getPriceForInitializeAction() public {
        PriceInfo memory price = oracleMiddleware.parseAndValidatePrice(
            uint128(block.timestamp - 24 seconds), ProtocolAction.Initialize, abi.encode("someDateToValidate")
        );
        assertEq(price.price, 2000 gwei, "Price should be 2000 gwei");
    }

    function test_getPriceForInitiateDepositAction() public {
        PriceInfo memory price = oracleMiddleware.parseAndValidatePrice(
            uint128(block.timestamp - 24 seconds), ProtocolAction.InitiateDeposit, abi.encode("someDateToValidate")
        );
        assertEq(price.price, 2000 gwei, "Price should be 2000 gwei");
    }

    function test_getPriceForValidateDepositAction() public {
        PriceInfo memory price = oracleMiddleware.parseAndValidatePrice(
            uint128(block.timestamp - 24 seconds), ProtocolAction.ValidateDeposit, abi.encode("someDateToValidate")
        );
        assertEq(price.price, 2000 gwei - 20 gwei, "Price should be 2000 gwei");
    }

    function test_getPriceForInitiateWithdrawalAction() public {
        PriceInfo memory price = oracleMiddleware.parseAndValidatePrice(
            uint128(block.timestamp - 24 seconds), ProtocolAction.InitiateWithdrawal, abi.encode("someDateToValidate")
        );
        assertEq(price.price, 2000 gwei, "Price should be 2000 gwei");
    }

    function test_getPriceForValidateWithdrawalAction() public {
        PriceInfo memory price = oracleMiddleware.parseAndValidatePrice(
            uint128(block.timestamp - 24 seconds), ProtocolAction.ValidateWithdrawal, abi.encode("someDateToValidate")
        );
        assertEq(price.price, 2000 gwei - 20 gwei, "Price should be 2000 gwei");
    }

    function test_getPriceForInitiateOpenPositionAction() public {
        PriceInfo memory price = oracleMiddleware.parseAndValidatePrice(
            uint128(block.timestamp - 24 seconds), ProtocolAction.InitiateOpenPosition, abi.encode("someDateToValidate")
        );
        assertEq(price.price, 2000 gwei, "Price should be 2000 gwei");
    }

    function test_getPriceForValidateOpenPositionAction() public {
        PriceInfo memory price = oracleMiddleware.parseAndValidatePrice(
            uint128(block.timestamp - 24 seconds), ProtocolAction.ValidateOpenPosition, abi.encode("someDateToValidate")
        );
        assertEq(price.price, 2000 gwei + 20 gwei, "Price should be 2000 gwei");
    }

    function test_getPriceForInitiateClosePositionAction() public {
        PriceInfo memory price = oracleMiddleware.parseAndValidatePrice(
            uint128(block.timestamp - 24 seconds),
            ProtocolAction.InitiateClosePosition,
            abi.encode("someDateToValidate")
        );
        assertEq(price.price, 2000 gwei, "Price should be 2000 gwei");
    }

    function test_getPriceForValidateClosePositionAction() public {
        PriceInfo memory price = oracleMiddleware.parseAndValidatePrice(
            uint128(block.timestamp - 24 seconds),
            ProtocolAction.ValidateClosePosition,
            abi.encode("someDateToValidate")
        );
        assertEq(price.price, 2000 gwei - 20 gwei, "Price should be 2000 gwei");
    }

    function test_getPriceForLiquidationAction() public {
        PriceInfo memory price = oracleMiddleware.parseAndValidatePrice(
            uint128(block.timestamp - 24 seconds), ProtocolAction.Liquidation, abi.encode("someDateToValidate")
        );
        assertEq(price.price, 2000 gwei - 20 gwei, "Price should be 2000 gwei");
    }
}

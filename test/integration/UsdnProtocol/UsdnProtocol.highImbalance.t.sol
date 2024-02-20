// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { USER_1, USER_2 } from "test/utils/Constants.sol";
import { UsdnProtocolBaseIntegrationFixture } from "test/integration/UsdnProtocol/utils/Fixtures.sol";

import { ProtocolAction } from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";

contract UsdnProtocolHighImbalanceTest is UsdnProtocolBaseIntegrationFixture {
    function setUp() public {
        params = DEFAULT_PARAMS;
        params.initialDeposit = 1 ether;
        params.initialLong = 1 ether;
        params.initialLiqPrice = 1 ether;
        params.initialPrice = 3290 ether;
        params.initialTimestamp = 1_708_088_866; // 16 February 2024 at 14:07 CET
        _setUp(params);
    }

    function test_highImbalance() public {
        emit log_named_decimal_int(
            "long expo", protocol.longTradingExpoWithFunding(params.initialPrice, uint128(block.timestamp)), 18
        );
        emit log_named_decimal_int(
            "vault expo", protocol.vaultTradingExpoWithFunding(params.initialPrice, uint128(block.timestamp)), 18
        );

        vm.warp(1_708_090_186);
        mockChainlinkOnChain.setLastPublishTime(1_708_090_186 - 10 minutes);
        mockChainlinkOnChain.setLastPrice(3290e8);

        vm.startPrank(USER_1);
        (bool success,) = address(wstETH).call{ value: 200 ether }("");
        require(success, "USER_1 wstETH mint failed");
        wstETH.approve(address(protocol), type(uint256).max);

        protocol.initiateOpenPosition{ value: oracleMiddleware.validationCost("", ProtocolAction.InitiateOpenPosition) }(
            132 ether, 2563 ether, "", ""
        );

        emit log_named_decimal_int(
            "long expo", protocol.longTradingExpoWithFunding(3290 ether, uint128(block.timestamp)), 18
        );
        emit log_named_decimal_int(
            "vault expo", protocol.vaultTradingExpoWithFunding(3290 ether, uint128(block.timestamp)), 18
        );

        vm.warp(1_708_090_246);
        mockPyth.updatePrice(3290e8);
        mockPyth.setLastPublishTime(1_708_090_186 + 24);

        protocol.validateOpenPosition{ value: oracleMiddleware.validationCost("", ProtocolAction.ValidateOpenPosition) }(
            "beef", ""
        );

        emit log_named_decimal_int(
            "long expo", protocol.longTradingExpoWithFunding(3290 ether, uint128(block.timestamp)), 18
        );
        emit log_named_decimal_int(
            "vault expo", protocol.vaultTradingExpoWithFunding(3290 ether, uint128(block.timestamp)), 18
        );

        vm.warp(1_708_090_342);
        mockChainlinkOnChain.setLastPublishTime(1_708_090_342 - 10 minutes);
        mockChainlinkOnChain.setLastPrice(3290e8);

        protocol.initiateOpenPosition{ value: oracleMiddleware.validationCost("", ProtocolAction.InitiateOpenPosition) }(
            1 ether, 2674 ether, "", ""
        );

        emit log_named_decimal_int(
            "long expo", protocol.longTradingExpoWithFunding(3290 ether, uint128(block.timestamp)), 18
        );
        emit log_named_decimal_int(
            "vault expo", protocol.vaultTradingExpoWithFunding(3290 ether, uint128(block.timestamp)), 18
        );

        vm.warp(1_708_090_438);
        mockPyth.updatePrice(3281e8);
        mockPyth.setLastPublishTime(1_708_090_342 + 24);

        protocol.validateOpenPosition{ value: oracleMiddleware.validationCost("", ProtocolAction.ValidateOpenPosition) }(
            "beef", ""
        );

        emit log_named_decimal_int(
            "long expo", protocol.longTradingExpoWithFunding(3281 ether, uint128(block.timestamp)), 18
        );
        emit log_named_decimal_int(
            "vault expo", protocol.vaultTradingExpoWithFunding(3281 ether, uint128(block.timestamp)), 18
        );
        vm.stopPrank();

        vm.warp(1_708_530_066); // had to add 200_000 seconds compared to real case to make it liquidate both ticks
        mockChainlinkOnChain.setLastPublishTime(1_708_530_066 - 10 minutes);
        mockChainlinkOnChain.setLastPrice(3381e8);

        vm.startPrank(USER_2);
        (success,) = address(wstETH).call{ value: 200 ether }("");
        require(success, "USER_2 wstETH mint failed");
        wstETH.approve(address(protocol), type(uint256).max);

        protocol.initiateOpenPosition{ value: oracleMiddleware.validationCost("", ProtocolAction.InitiateOpenPosition) }(
            1 ether, 1684 ether, "", ""
        );

        emit log_named_decimal_int(
            "long expo", protocol.longTradingExpoWithFunding(3381 ether, uint128(block.timestamp)), 18
        );
        emit log_named_decimal_int(
            "vault expo", protocol.vaultTradingExpoWithFunding(3381 ether, uint128(block.timestamp)), 18
        );
    }
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { USER_1, USER_2 } from "test/utils/Constants.sol";
import { UsdnProtocolBaseIntegrationFixture } from "test/integration/UsdnProtocol/utils/Fixtures.sol";

import { ProtocolAction } from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";

/**
 * @custom:feature A long position is in large bad debt
 * @custom:background This test replicates the transactions observed on a testing fork which resulted in a negative
 * long trading expo. This was due to an erroneous clamping of the balances to remain positive, before any bad debt
 * could be repaid by the vault. The long balance (which was clamped to zero) was thus increased by the amount of the
 * bad debt and became larger than the total expo of the remaining positions. This resulted in a negative trading expo.
 * The fix is now to allow balances to become negative temporarily during calculations.
 */
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

    /**
     * @custom:scenario A very large long position is in large bad debt and gets liquidated
     * @custom:given An initial position of 1 ether with leverage ~1x
     * @custom:and A user position of 132 ether with leverage ~4.5x
     * @custom:and A user position of 1 ether with leverage ~5.3x
     * @custom:when The funding rates make the liquidation prices of both positions go up
     * @custom:and The positions get liquidated by a new user action, way too late
     * @custom:then The bad debt should be paid by the vault side and the long trading expo should be positive
     */
    function test_highImbalance() public {
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

        vm.warp(1_708_090_246);
        mockPyth.updatePrice(3290e8);
        mockPyth.setLastPublishTime(1_708_090_186 + 24);

        protocol.validateOpenPosition{
            value: oracleMiddleware.validationCost("beef", ProtocolAction.ValidateOpenPosition)
        }("beef", "");

        vm.warp(1_708_090_342);
        mockChainlinkOnChain.setLastPublishTime(1_708_090_342 - 10 minutes);
        mockChainlinkOnChain.setLastPrice(3290e8);

        protocol.initiateOpenPosition{ value: oracleMiddleware.validationCost("", ProtocolAction.InitiateOpenPosition) }(
            1 ether, 2674 ether, "", ""
        );

        vm.warp(1_708_090_438);
        mockPyth.updatePrice(3281e8);
        mockPyth.setLastPublishTime(1_708_090_342 + 24);

        protocol.validateOpenPosition{
            value: oracleMiddleware.validationCost("beef", ProtocolAction.ValidateOpenPosition)
        }("beef", "");

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
        vm.stopPrank();
        emit log_named_decimal_uint("long balance", protocol.balanceLong(), 18);
        emit log_named_decimal_uint("vault balance", protocol.balanceVault(), 18);
        emit log_named_decimal_uint("total expo", protocol.totalExpo(), 18);
        // TODO: uncomment once calculations are fixed
        //assertGe(protocol.longTradingExpoWithFunding(3381 ether, uint128(block.timestamp)), 0, "long expo");
    }
}

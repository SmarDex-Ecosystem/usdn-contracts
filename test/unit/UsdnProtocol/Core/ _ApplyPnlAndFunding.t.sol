// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { ADMIN, USER_1 } from "../../../utils/Constants.sol";
import { UsdnProtocolBaseFixture } from "../utils/Fixtures.sol";

contract TestUsdnProtocolCoreApplyPnlAndFunding is UsdnProtocolBaseFixture {
    function setUp() public {
        params = DEFAULT_PARAMS;
        params.flags.enableProtocolFees = true;
        params.flags.enableFunding = true;
        super._setUp(params);
    }

    /**
     * @custom:scenario Calling the `_applyPnlAndFunding` function with a new price at $3000
     * @custom:given A USDN protocol initialized with an `initialPrice` at $2000 and funding enabled
     * @custom:when The `_applyPnlAndFunding` function is called with a new price at 3000$ and a timestamp too old
     * @custom:then The state values are not updated and returned values are the same as before
     */
    function test_applyPnlAndFundingWithTooOldPrice() external {
        uint128 oldPrice = protocol.getLastPrice();
        uint128 newPrice = 3000 ether;

        vm.warp(protocol.getLastUpdateTimestamp() + 12 hours); // be consistent with funding tests

        // Taking snapshot of the state and expected values
        int256 longBalanceBefore = int256(protocol.getBalanceLong());
        int256 vaultBalanceBefore = int256(protocol.getBalanceVault());

        // Calling the function
        ApplyPnlAndFundingData memory data = protocol.i_applyPnlAndFunding(newPrice, 0);

        // Testing state values
        assertEq(protocol.getLastPrice(), oldPrice, "PriceOld: _lastPrice should not be updated");
        assertEq(
            protocol.getLastUpdateTimestamp(),
            protocol.getLastUpdateTimestamp(),
            "PriceOld: last update timestamp should not be updated"
        );
        assertEq(protocol.getEMA(), protocol.getEMA(), "PriceOld: EMA should not be updated");

        // Testing returned values
        assertEq(data.lastPrice, oldPrice, "PriceOld: last price should not be updated");
        assertEq(data.isPriceRecent, false, "PriceOld: price is not recent");
        assertEq(data.tempLongBalance, longBalanceBefore, "PriceOld: long balance should not be updated");
        assertEq(data.tempVaultBalance, vaultBalanceBefore, "PriceOld: vault balance should not be updated");
    }

    /**
     * @custom:scenario Calling the `_applyPnlAndFunding` function with a new price at $2500
     * @custom:given A USDN protocol initialized with an `initialPrice` at $2000 and funding disabled
     * @custom:when The `_applyPnlAndFunding` function is called with the same price
     * @custom:then The state values are updated but remain unchanged
     */
    function test_applyPnlAndFunding() external {
        vm.startPrank(ADMIN);
        protocol.setFundingSF(0);
        protocol.resetEMA();
        vm.stopPrank();

        uint128 oldPrice = protocol.getLastPrice();
        uint128 newPrice = 2500 ether;

        _applyPnlAndFundingScenarioAndAssertsUtil(oldPrice, newPrice);
    }

    /**
     * @custom:scenario Calling the `_applyPnlAndFunding` function with a new price at $2000
     * @custom:given A USDN protocol initialized with an `initialPrice` at $2000 and funding enabled
     * @custom:when The `_applyPnlAndFunding` function is called with the same price
     * @custom:then The state values are updated to take into account the funding
     */
    function test_applyPnlAndFundingWithFunding() external {
        uint128 newPrice = protocol.getLastPrice();
        uint128 oldPrice = newPrice;

        _applyPnlAndFundingScenarioAndAssertsUtil(oldPrice, newPrice);
    }

    /**
     * @custom:scenario Calling the `_applyPnlAndFunding` function with a new price at $2500
     * @custom:given A USDN protocol initialized with an `initialPrice` at $2000 and funding disabled
     * @custom:when The `_applyPnlAndFunding` function is called with a new price at 2500$
     * @custom:then The state values are updated to take into account the pnl
     */
    function test_applyPnlAndFundingDifferentPrice() external {
        vm.startPrank(ADMIN);
        protocol.setFundingSF(0);
        protocol.resetEMA();
        vm.stopPrank();

        uint128 oldPrice = protocol.getLastPrice();
        uint128 newPrice = oldPrice;

        _applyPnlAndFundingScenarioAndAssertsUtil(oldPrice, newPrice);
    }

    /**
     * @custom:scenario Calling the `_applyPnlAndFunding` function with a new price at $2500
     * @custom:given A USDN protocol initialized with an `initialPrice` at $2000 and funding enabled
     * @custom:when The `_applyPnlAndFunding` function is called with a new price at 2500$
     * @custom:then The state values are updated to take into account the pnl and funding
     */
    function test_applyPnlAndFundingDifferentPriceWithFunding() external {
        uint128 oldPrice = protocol.getLastPrice();
        uint128 newPrice = 2500 ether;

        _applyPnlAndFundingScenarioAndAssertsUtil(oldPrice, newPrice);
    }

    /**
     * @custom:scenario Calling the `_applyPnlAndFunding` function with a new price at `newPrice`
     * @custom:given A USDN protocol initialized with an `initialPrice` at `oldPrice` and a long position opened.
     * @param oldPrice The initial price
     * @param newPrice The new price to apply when calling `_applyPnlAndFunding`
     */
    function _applyPnlAndFundingScenarioAndAssertsUtil(uint128 oldPrice, uint128 newPrice) internal {
        // Opening a long and wait 12 hours to make the protocol imbalanced and have funding
        setUpUserPositionInLong(
            OpenParams({
                user: USER_1,
                untilAction: ProtocolAction.InitiateOpenPosition,
                positionSize: 10 ether,
                desiredLiqPrice: oldPrice / 2,
                price: oldPrice
            })
        );
        vm.warp(protocol.getLastUpdateTimestamp() + 12 hours); // be consistent with funding tests

        // Taking snapshot of the state and expected values
        int256 longBalanceBefore = int256(protocol.getBalanceLong());
        int256 vaultBalanceBefore = int256(protocol.getBalanceVault());
        int256 fundingPerDayBefore = protocol.getLastFundingPerDay(); // no funding yet
        int256 expectedFeeAsset;
        int256 expectedFundingAsset;
        int256 expectedFundingPerDay;
        {
            int256 emaBefore = protocol.getEMA();
            (expectedFundingPerDay,) = protocol.i_fundingPerDay(emaBefore);
            int256 expectedFunding = expectedFundingPerDay / 2; // 24/2 hours passed
            expectedFundingAsset =
                expectedFunding * protocol.getLongTradingExpo(oldPrice) / int256(10) ** protocol.FUNDING_RATE_DECIMALS();
            int256 protocolFeeBps = int256(protocol.i_protocolFeeBps());
            expectedFeeAsset = expectedFundingAsset * protocolFeeBps / int256(protocol.BPS_DIVISOR());
        }

        int256 expectedEma = protocol.calcEMA(expectedFundingPerDay, 12 hours);
        int256 expectedPnl = protocol.getLongTradingExpo(oldPrice)
            * (int256(int128(newPrice)) - int256(int128(oldPrice))) / int256(int128(newPrice));

        // Calling the function
        vm.expectEmit();
        emit LastFundingPerDayUpdated(expectedFundingPerDay, block.timestamp);
        ApplyPnlAndFundingData memory data = protocol.i_applyPnlAndFunding(newPrice, uint128(block.timestamp));

        // Testing lastFundingPerDay
        if (params.flags.enableFunding) {
            assertEq(
                protocol.getLastFundingPerDay(), expectedFundingPerDay, "After the long, the funding should increase"
            );
        } else {
            assertEq(
                protocol.getLastFundingPerDay(),
                fundingPerDayBefore,
                "Funding is disabled, the funding should not change"
            );
        }

        // Testing state values
        assertEq(protocol.getLastPrice(), newPrice, "_lastPrice should be equal to i_applyPnlAndFunding new price");
        assertEq(protocol.getLastUpdateTimestamp(), block.timestamp, "last update timestamp should be updated");
        assertEq(protocol.getEMA(), expectedEma, "EMA should be updated");

        // Testing returned values
        assertEq(data.lastPrice, newPrice, "last price should be updated to newPrice");
        assertEq(data.isPriceRecent, true, "price is recent");

        if (expectedFundingAsset > 0) {
            assertEq(
                data.tempLongBalance,
                longBalanceBefore + expectedPnl - expectedFundingAsset,
                "funding positive: long balance"
            );
            assertEq(
                data.tempVaultBalance,
                vaultBalanceBefore - expectedPnl + (expectedFundingAsset - expectedFeeAsset),
                "funding positive: vault balance"
            );
        } else {
            assertEq(
                data.tempLongBalance,
                longBalanceBefore + expectedPnl - (expectedFundingAsset - expectedFeeAsset),
                "funding <= 0: long balance"
            );
            assertEq(
                data.tempVaultBalance,
                vaultBalanceBefore - expectedPnl + expectedFundingAsset,
                "funding <= 0: vault balance"
            );
        }
    }
}

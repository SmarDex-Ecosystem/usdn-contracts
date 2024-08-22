// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { UsdnProtocolBaseFixture } from "../utils/Fixtures.sol";

contract TestUsdnProtocolCoreApplyPnlAndFunding is UsdnProtocolBaseFixture {
    function setUp() public {
        params = DEFAULT_PARAMS;
        params.flags.enableProtocolFees = true;
    }

    /**
     * @custom:given A USDN protocol initialized with an `initialPrice` at 2000$ and funding disabled
     * @custom:when The `_applyPnlAndFunding` function is called with the same price
     * @custom:then The state values are updated but remain unchanged
     */
    function test_applyPnlAndFunding() external {
        super._setUp(params);

        uint128 oldPrice = protocol.getLastPrice();
        uint128 newPrice = 2500 ether;

        _applyPnlAndFundingScenarioAndAssertsUtil(oldPrice, newPrice);
    }

    /**
     * @custom:given A USDN protocol initialized with an `initialPrice` at 2000$ and funding enabled
     * @custom:when The `_applyPnlAndFunding` function is called with the same price
     * @custom:then The state values are updated to take into account the funding
     */
    function test_applyPnlAndFundingWithFunding() external {
        params.flags.enableFunding = true;
        super._setUp(params);

        uint128 newPrice = protocol.getLastPrice();
        uint128 oldPrice = newPrice;

        _applyPnlAndFundingScenarioAndAssertsUtil(oldPrice, newPrice);
    }

    /**
     * @custom:given A USDN protocol initialized with an `initialPrice` at 2000$ and funding disabled
     * @custom:when The `_applyPnlAndFunding` function is called with a new price at 2500$
     * @custom:then The state values are updated to take into account the pnl
     */
    function test_applyPnlAndFundingDifferentPrice() external {
        params.flags.enableFunding = false;
        super._setUp(params);

        uint128 oldPrice = protocol.getLastPrice();
        uint128 newPrice = 2500 ether;

        _applyPnlAndFundingScenarioAndAssertsUtil(oldPrice, newPrice);
    }

    /**
     * @custom:given A USDN protocol initialized with an `initialPrice` at 2000$ and funding enabled
     * @custom:when The `_applyPnlAndFunding` function is called with a new price at 2500$
     * @custom:then The state values are updated to take into account the pnl and funding
     */
    function test_applyPnlAndFundingDifferentPriceWithFunding() external {
        params.flags.enableFunding = true;
        super._setUp(params);

        uint128 oldPrice = protocol.getLastPrice();
        uint128 newPrice = 2500 ether;

        _applyPnlAndFundingScenarioAndAssertsUtil(oldPrice, newPrice);
    }

    /**
     * @custom:given A USDN protocol initialized with an `initialPrice` at `oldPrice` and a long position opened. Call
     * the `_applyPnlAndFunding` function with a new price at `newPrice`
     * @param oldPrice The old price (initial price)
     * @param newPrice The new price (new price to apply when calling `_applyPnlAndFunding`)
     */
    function _applyPnlAndFundingScenarioAndAssertsUtil(uint128 oldPrice, uint128 newPrice) internal {
        // Opening a long and wait 12 hours to make the protocol imbalanced and have funding
        uint128 amount = 10 ether;
        bytes memory priceData = abi.encode(oldPrice);
        wstETH.mintAndApprove(address(this), amount, address(protocol), type(uint256).max);
        protocol.initiateOpenPosition{ value: protocol.getSecurityDepositValue() }(
            amount,
            oldPrice / 2,
            payable(address(this)),
            payable(address(this)),
            NO_PERMIT2,
            priceData,
            EMPTY_PREVIOUS_DATA
        );
        vm.warp(protocol.getLastUpdateTimestamp() + 12 hours); // be consistant with funding tests

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
        ApplyPnlAndFundingData memory datas = protocol.i_applyPnlAndFunding(newPrice, uint128(block.timestamp));

        // Testing state values
        assertEq(protocol.getLastPrice(), newPrice, "_lastPrice should be equal to i_applyPnlAndFunding new price");
        assertEq(protocol.getLastUpdateTimestamp(), block.timestamp, "last update timestamp should be updated");
        assertEq(protocol.getEMA(), expectedEma, "EMA should be updated");
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

        // Testing returned values
        assertEq(datas.lastPrice, newPrice, "last price should be updated to newPrice");
        assertEq(datas.isPriceRecent, true, "price is recent");

        if (expectedFundingAsset > 0) {
            assertEq(
                datas.tempLongBalance,
                longBalanceBefore + expectedPnl - expectedFundingAsset,
                "funding positive: long balance"
            );
            assertEq(
                datas.tempVaultBalance,
                vaultBalanceBefore - expectedPnl + (expectedFundingAsset - expectedFeeAsset),
                "funding positive: vault balance"
            );
        } else {
            assertEq(
                datas.tempLongBalance,
                longBalanceBefore + expectedPnl - (expectedFundingAsset - expectedFeeAsset),
                "funding <= 0: long balance"
            );
            assertEq(
                datas.tempVaultBalance,
                vaultBalanceBefore - expectedPnl + expectedFundingAsset,
                "funding <= 0: vault balance"
            );
        }
    }
}

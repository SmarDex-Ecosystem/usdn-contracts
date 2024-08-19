// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { console2 } from "forge-std/Test.sol";

import { UsdnProtocolBaseFixture } from "../utils/Fixtures.sol";

import { SignedMath } from "../../../../src/libraries/SignedMath.sol";

contract TestUsdnProtocolCoreApplyPnlAndFunding is UsdnProtocolBaseFixture {
    using SignedMath for int256;

    function setUp() public {
        params = DEFAULT_PARAMS;
    }

    /**
     * @custom:given A USDN protocol initialized with an `initialPrice` at 2000$ and funding disabled
     * @custom:when The `_applyPnlAndFunding` function is called with the same price
     * @custom:then The state values are updated but remain unchanged
     */
    function test_applyPnlAndFunding() external {
        super._setUp(params);

        ApplyPnlAndFundingData memory datas =
            protocol.i_applyPnlAndFunding(DEFAULT_PARAMS.initialPrice, uint128(block.timestamp));
        int256 fundingBefore = protocol.getLastFundingPerDay();

        // Testing state values
        assertEq(
            protocol.getLastPrice(),
            DEFAULT_PARAMS.initialPrice,
            "_lastPrice should be equal to i_applyPnlAndFunding new price"
        );
        assertEq(protocol.getLastUpdateTimestamp(), block.timestamp, "last update timestamp should be updated");
        assertEq(protocol.getLastFundingPerDay(), fundingBefore, "price didn't change so funding should not change");

        // Testing returned values (no funding in this scenario)
        assertEq(datas.lastPrice, DEFAULT_PARAMS.initialPrice, "last price should not change");
        assertEq(datas.isPriceRecent, true, "price is recent");
        assertEq(
            datas.tempLongBalance,
            protocol.i_longAssetAvailable(DEFAULT_PARAMS.initialPrice),
            "long balance should not change"
        );
        assertEq(
            datas.tempVaultBalance,
            protocol.i_vaultAssetAvailable(DEFAULT_PARAMS.initialPrice),
            "vault balance should not change"
        );
    }

    /**
     * @custom:given A USDN protocol initialized with an `initialPrice` at 2000$ and funding enabled
     * @custom:when The `_applyPnlAndFunding` function is called with the same price
     * @custom:then The state values are updated todo rework this sentence and speak about funding
     */
    function test_applyPnlAndFundingWithFunding() external {
        params.flags.enableFunding = true;
        super._setUp(params);

        uint128 newPrice = protocol.getLastPrice();

        int256 fundingPerDayBefore;
        int256 fundAsset;
        (fundAsset, fundingPerDayBefore) = protocol.i_fundingAsset(uint128(block.timestamp), protocol.get_EMA());
        (, int256 fundAssetWithFee) = protocol.i_calculateFee(fundAsset);

        vm.warp(block.timestamp + 24 hours); // be consistant with funding tests

        ApplyPnlAndFundingData memory datas = protocol.i_applyPnlAndFunding(newPrice, uint128(block.timestamp));

        // Testing state values
        assertEq(protocol.getLastPrice(), newPrice, "_lastPrice should be equal to i_applyPnlAndFunding new price");
        assertEq(protocol.getLastUpdateTimestamp(), block.timestamp, "last update timestamp should be updated");
        assertEq(
            protocol.getLastFundingPerDay(),
            fundingPerDayBefore,
            "price didn't change so funding should not change" // todo it should change because protocol is imbalanced
        );
        assertEq(protocol.get_EMA(), 3 ether * 10 ** -4, "funding skew should be 0.0003");

        // Testing returned values
        assertEq(datas.lastPrice, newPrice, "last price should be updated to newPrice");
        assertEq(datas.isPriceRecent, true, "price is recent");
        // assertEq(datas.tempLongBalance, int256(protocol.i_longAssetAvailable(newPrice).safeSub(fundAssetWithFee)),
        // "long balance should be updated to count funding");
        // assertEq(datas.tempVaultBalance, protocol.i_vaultAssetAvailable(newPrice).safeAdd(fundAssetWithFee), "vault
        // balance should be updated to count funding");
    }

    /**
     * @custom:given A USDN protocol initialized with an `initialPrice` at 2000$ and funding disabled
     * @custom:when The `_applyPnlAndFunding` function is called with a new price at 2500$
     * @custom:then The state values are updated todo rework this sentence and speak about pnl
     */
    function test_applyPnlAndFundingDifferentPrice() external {
        params.flags.enableFunding = false;
        super._setUp(params);

        uint128 oldPrice = protocol.getLastPrice();
        uint128 newPrice = 2500 ether;
        (, int256 fundingPerDayBefore) = protocol.i_fundingAsset(uint128(block.timestamp), protocol.get_EMA());
        int256 expectedPnl = protocol.getLongTradingExpo(oldPrice)
            * (int256(int128(newPrice)) - int256(int128(oldPrice))) / int256(int128(newPrice));
        int256 longBalanceBefore = int256(protocol.getBalanceLong());
        int256 vaultBalanceBefore = int256(protocol.getBalanceVault());

        vm.warp(block.timestamp + 24 hours); // be consistant with funding tests

        ApplyPnlAndFundingData memory datas = protocol.i_applyPnlAndFunding(newPrice, uint128(block.timestamp));

        // Testing state values
        assertEq(protocol.getLastPrice(), newPrice, "_lastPrice should be equal to i_applyPnlAndFunding new price");
        assertEq(protocol.getLastUpdateTimestamp(), block.timestamp, "last update timestamp should be updated");
        assertEq(
            protocol.getLastFundingPerDay(), fundingPerDayBefore, "funding are disabled and therefore should not change"
        );

        // Testing returned values
        assertEq(datas.lastPrice, newPrice, "last price should be updated to newPrice");
        assertEq(datas.isPriceRecent, true, "price is recent");
        assertEq(datas.tempLongBalance, expectedPnl + longBalanceBefore, "long balance should be updated to count pnl");
        assertEq(
            datas.tempVaultBalance, vaultBalanceBefore - expectedPnl, "vault balance should be updated to count pnl"
        );
    }

    /**
     * @custom:given A USDN protocol initialized with an `initialPrice` at 2000$ and funding enabled
     * @custom:when The `_applyPnlAndFunding` function is called with a new price at 2500$
     * @custom:then The state values are updated todo rework this sentence and speak about pnl and funding
     */
    function test_applyPnlAndFundingDifferentPriceWithFunding() external {
        params.flags.enableFunding = true;
        params.initialDeposit = 4 ether; // making the protocol imbalanced
        super._setUp(params);

        uint128 oldPrice = protocol.getLastPrice();
        uint128 newPrice = 2500 ether;
        int256 fundingPerDayBefore;
        int256 fundAsset;
        (fundAsset, fundingPerDayBefore) = protocol.i_fundingAsset(uint128(block.timestamp), protocol.get_EMA());
        (, int256 fundAssetWithFee) = protocol.i_calculateFee(fundAsset);
        int256 expectedPnl = protocol.getLongTradingExpo(oldPrice)
            * (int256(int128(newPrice)) - int256(int128(oldPrice))) / int256(int128(newPrice));
        int256 longBalanceBefore = int256(protocol.getBalanceLong());
        int256 vaultBalanceBefore = int256(protocol.getBalanceVault());

        vm.warp(block.timestamp + 24 hours); // let funding happen

        ApplyPnlAndFundingData memory datas = protocol.i_applyPnlAndFunding(newPrice, uint128(block.timestamp));

        // Testing state values
        assertEq(protocol.getLastPrice(), newPrice, "_lastPrice should be equal to i_applyPnlAndFunding new price");
        assertEq(protocol.getLastUpdateTimestamp(), block.timestamp, "last update timestamp should be updated");
        assertEq(protocol.getLastFundingPerDay(), fundingPerDayBefore, "funding should be updated"); // todo

        // Testing returned values
        assertEq(datas.lastPrice, newPrice, "last price should be updated to newPrice");
        assertEq(datas.isPriceRecent, true, "price is recent");
        // assertEq(datas.tempLongBalance, longBalanceBefore + expectedPnl - fundAssetWithFee, "long balance should be
        // updated to count pnl and funding");
        // assertEq(datas.tempVaultBalance, vaultBalanceBefore - expectedPnl + fundAssetWithFee, "vault balance should
        // be updated to count pnl and funding");
    }
}

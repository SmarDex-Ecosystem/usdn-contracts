// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { console2 } from "forge-std/Test.sol";

import { UsdnProtocolBaseFixture } from "../utils/Fixtures.sol";

import { SignedMath } from "../../../../src/libraries/SignedMath.sol";

contract TestUsdnProtocolCoreApplyPnlAndFunding is UsdnProtocolBaseFixture {
    using SignedMath for int256;

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

        vm.warp(block.timestamp + 24 hours); // be consistant with funding tests

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
        uint128 oldPrice = newPrice;

        _applyPnlAndFundingScenarioAndAssertsUtil(oldPrice, newPrice);
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

        _applyPnlAndFundingScenarioAndAssertsUtil(oldPrice, newPrice);
    }

    /**
     * @custom:given A USDN protocol initialized with an `initialPrice` at 2000$ and funding enabled
     * @custom:when The `_applyPnlAndFunding` function is called with a new price at 2500$
     * @custom:then The state values are updated todo rework this sentence and speak about pnl and funding
     */
    function test_applyPnlAndFundingDifferentPriceWithFunding() external {
        params.flags.enableFunding = true;
        // params.initialDeposit = 4 ether; // making the protocol imbalanced
        super._setUp(params);

        uint128 oldPrice = protocol.getLastPrice();
        uint128 newPrice = 2500 ether;

        _applyPnlAndFundingScenarioAndAssertsUtil(oldPrice, newPrice);
    }

    function _applyPnlAndFundingScenarioAndAssertsUtil(uint128 oldPrice, uint128 newPrice) internal {
        // Opening a long and wait 24 hours to make the protocol imbalanced and have funding
        bytes memory priceData = abi.encode(newPrice);
        uint128 amount = 10 ether;
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
        vm.warp(block.timestamp + 12 hours - 1 seconds); // be consistant with funding tests

        // Taking snapshot of the state and expected values
        int256 longBalanceBefore = int256(protocol.getBalanceLong());
        int256 vaultBalanceBefore = int256(protocol.getBalanceVault());
        int256 fundingPerDayBefore = protocol.getLastFundingPerDay(); // no funding yet
        int256 expectedFeeAsset;
        int256 expectedFundingAsset;
        {
            int256 emaBefore = protocol.get_EMA();
            (int256 expectedFundingPerDay,) = protocol.i_fundingPerDay(emaBefore);
            int256 expectedFunding = expectedFundingPerDay / 2; // 24/2 hours passed
            expectedFundingAsset =
                expectedFunding * protocol.getLongTradingExpo(newPrice) / int256(10) ** protocol.FUNDING_RATE_DECIMALS();
            int256 protocolFeeBps = int256(protocol.i_protocolFeeBps());
            expectedFeeAsset = expectedFundingAsset * protocolFeeBps / int256(protocol.BPS_DIVISOR());
        }
        int256 expectedPnl = protocol.getLongTradingExpo(oldPrice)
            * (int256(int128(newPrice)) - int256(int128(oldPrice))) / int256(int128(newPrice));

        // Calling the function
        ApplyPnlAndFundingData memory datas = protocol.i_applyPnlAndFunding(newPrice, uint128(block.timestamp));

        // Testing state values
        assertEq(protocol.getLastPrice(), newPrice, "_lastPrice should be equal to i_applyPnlAndFunding new price");
        assertEq(protocol.getLastUpdateTimestamp(), block.timestamp, "last update timestamp should be updated");
        if (params.flags.enableFunding) {
            assertGt( // todo: have the precise value
                protocol.getLastFundingPerDay(),
                fundingPerDayBefore,
                "After the long, the funding should increase and be updated"
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

        console2.log("datas.tempLongBalance", datas.tempLongBalance);
        console2.log("longBalanceBefore", longBalanceBefore);
        console2.log("expectedFundingAsset", expectedFundingAsset);
        console2.log("expectedFeeAsset", expectedFeeAsset);
        console2.log("expectedPnl", expectedPnl);
        console2.log("expectedFundingAsset - expectedFeeAsset", expectedFundingAsset - expectedFeeAsset);
        console2.log(
            "longBalanceBefore - (expectedFundingAsset - expectedFeeAsset)",
            longBalanceBefore - (expectedFundingAsset - expectedFeeAsset)
        );
        if (expectedFundingAsset > 0) {
            assertEq(
                datas.tempLongBalance,
                longBalanceBefore + expectedPnl - expectedFundingAsset,
                "long balance should be updated to count funding"
            );
            assertEq(
                datas.tempVaultBalance,
                vaultBalanceBefore - expectedPnl + (expectedFundingAsset - expectedFeeAsset),
                "vault balance should be updated to count funding"
            );
        } else {
            assertEq(
                datas.tempLongBalance,
                longBalanceBefore + expectedPnl - (expectedFundingAsset - expectedFeeAsset),
                "long balance should be updated to count funding"
            );
            assertEq(
                datas.tempVaultBalance,
                vaultBalanceBefore - expectedPnl + expectedFundingAsset,
                "vault balance should be updated to count funding"
            );
        }
    }
}

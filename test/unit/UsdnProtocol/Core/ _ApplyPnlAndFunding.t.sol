// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { UsdnProtocolBaseFixture } from "../utils/Fixtures.sol";

import { SignedMath } from "../../../../src/libraries/SignedMath.sol";

contract TestUsdnProtocolCoreApplyPnlAndFunding is UsdnProtocolBaseFixture {
    using SignedMath for int256;

    function setUp() public {
        params = DEFAULT_PARAMS;
        super._setUp(params);
    }

    /**
     * @custom:given A USDN protocol initialized with an `initialPrice` at 2000$
     * @custom:when The `_applyPnlAndFunding` function is called with the same price
     * @custom:then The state values are updated but remain unchanged
     */
    function test_applyPnlAndFunding() external {
        ApplyPnlAndFundingData memory datas =
            protocol.i_applyPnlAndFunding(DEFAULT_PARAMS.initialPrice, uint128(block.timestamp));
        int256 fundingBefore = protocol.getLastFundingPerDay();

        // Testing state values
        assertEq(
            protocol.getLastPrice(),
            DEFAULT_PARAMS.initialPrice,
            "_lastPrice should be equal to i_applyPnlAndFunding new price"
        );
        assertEq(protocol.getLastUpdateTimestamp(), block.timestamp);
        assertEq(protocol.getLastFundingPerDay(), fundingBefore);

        // Testing returned values
        assertEq(datas.lastPrice, DEFAULT_PARAMS.initialPrice);
        assertEq(datas.isPriceRecent, true);
        assertEq(datas.tempLongBalance, protocol.i_longAssetAvailable(DEFAULT_PARAMS.initialPrice));
        assertEq(datas.tempVaultBalance, protocol.i_vaultAssetAvailable(DEFAULT_PARAMS.initialPrice));
    }

    /**
     * @custom:given A USDN protocol initialized with an `initialPrice` at 2000$
     * @custom:when The `_applyPnlAndFunding` function is called with a price at 2500$
     * @custom:then The state values `_lastPrice`, `_lastUpdateTimestamp`, `_lastFunding` are updated
     */
    function test_applyPnlAndFundingDifferentPrice() external {
        uint128 newPrice = 2500 ether;
        int256 fundingPerDayBefore;
        int256 fundAsset;
        (fundAsset, fundingPerDayBefore) = protocol.i_fundingAsset(uint128(block.timestamp), protocol.get_EMA());
        (, int256 fundAssetWithFee) = protocol.i_calculateFee(fundAsset);

        ApplyPnlAndFundingData memory datas = protocol.i_applyPnlAndFunding(2500 ether, uint128(block.timestamp));

        // Testing state values
        assertEq(protocol.getLastPrice(), newPrice, "_lastPrice should be equal to i_applyPnlAndFunding new price");
        assertEq(protocol.getLastUpdateTimestamp(), block.timestamp);
        assertEq(protocol.getLastFundingPerDay(), fundingPerDayBefore);

        // Testing returned values
        assertEq(datas.lastPrice, newPrice);
        assertEq(datas.isPriceRecent, true);
        assertEq(datas.tempLongBalance, int256(protocol.i_longAssetAvailable(newPrice).safeSub(fundAssetWithFee)));
        // assertEq(datas.tempVaultBalance, protocol.i_vaultAssetAvailable(2500 ether));
    }
}

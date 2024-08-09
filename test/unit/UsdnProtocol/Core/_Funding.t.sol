// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { UsdnProtocolBaseFixture } from "../utils/Fixtures.sol";
import { UsdnProtocolHandler } from "../utils/Handler.sol";

import { UsdnProtocolConstantsLibrary as Constants } from
    "../../../../src/UsdnProtocol/libraries/UsdnProtocolConstantsLibrary.sol";

/// @custom:feature The `_funding` function of `UsdnProtocolCoreLibrary`
contract TestUsdnProtocolCoreFunding is UsdnProtocolBaseFixture {
    UsdnProtocolHandler.FundingStorage s;
    int256 constant EMA = int256(3 * 10 ** (Constants.FUNDING_RATE_DECIMALS - 4));
    uint128 constant TIME_ELAPSED = 1000 seconds;

    function setUp() public {
        params = DEFAULT_PARAMS;
        params.flags.enableFunding = true;
        super._setUp(params);
        s = UsdnProtocolHandler.FundingStorage({
            totalExpo: protocol.getTotalExpo(),
            balanceLong: protocol.getBalanceLong(),
            balanceVault: protocol.getBalanceVault(),
            lastUpdateTimestamp: uint128(block.timestamp),
            fundingSF: protocol.getFundingSF()
        });
    }

    /**
     * @custom:scenario Funding calculation when no time has elapsed
     * @custom:given The timestamp is the same as the last update timestamp
     * @custom:when The funding is calculated
     * @custom:then The funding is 0
     * @custom:and The funding rate is unaffected by time
     * @custom:and The long exposure is as expected
     */
    function test_fundingNoTimeElapsed() public {
        (int256 funding, int256 fundingPerDay, int256 longExpo) = protocol.i_funding(s, s.lastUpdateTimestamp, EMA);
        assertEq(funding, 0, "funding");
        assertEq(fundingPerDay, protocol.getEMA(), "funding rate is unaffected time");
        assertEq(longExpo, int256(s.totalExpo - s.balanceLong), "longExpo");
    }

    /**
     * @custom:scenario Funding calculation when long exposure is greater than vault exposure
     * @custom:given The long trading expo is double that of the vault trading expo
     * @custom:and Some time has passed since the last update
     * @custom:when The funding is calculated
     * @custom:then The funding is positive and as expected
     * @custom:and The funding rate is positive and as expected
     * @custom:and The long exposure is as expected
     */
    function test_fundingTimeElapsedPositive() public {
        s.totalExpo = 2000 ether;
        s.balanceLong = 1000 ether;
        s.balanceVault = 500 ether;

        int256 longTradingExpo = int256(s.totalExpo - s.balanceLong);
        assertEq(longTradingExpo, 1000 ether, "longTradingExpo");
        uint256 numeratorSquared = uint256((longTradingExpo - int256(s.balanceVault)) ** 2);
        assertEq(numeratorSquared, 500 ether ** 2, "numeratorSquared");
        uint256 denominator = uint256(longTradingExpo * longTradingExpo);
        int256 expectedFundingPerDay = int256(
            numeratorSquared * s.fundingSF * 10 ** (Constants.FUNDING_RATE_DECIMALS - Constants.FUNDING_SF_DECIMALS)
                / denominator
        ) + EMA;
        assertGt(expectedFundingPerDay, 0, "positive funding");
        int256 expectedFunding = expectedFundingPerDay * int256(uint256(TIME_ELAPSED)) / 1 days;

        (int256 funding, int256 fundingPerDay, int256 longExpo) =
            protocol.i_funding(s, s.lastUpdateTimestamp + TIME_ELAPSED, EMA);
        assertEq(funding, expectedFunding, "funding");
        assertEq(fundingPerDay, expectedFundingPerDay, "funding rate");
        assertEq(longExpo, longTradingExpo, "longExpo");
    }

    /**
     * @custom:scenario Funding calculation when long exposure is less than vault exposure
     * @custom:given The long trading expo is half that of the vault trading expo
     * @custom:and Some time has passed since the last update
     * @custom:when The funding is calculated
     * @custom:then The funding is negative and as expected
     * @custom:and The funding rate is negative and as expected
     * @custom:and The long exposure is as expected
     */
    function test_fundingTimeElapsedNegative() public {
        s.totalExpo = 2000 ether;
        s.balanceLong = 1000 ether;
        s.balanceVault = 2000 ether;

        int256 longTradingExpo = int256(s.totalExpo - s.balanceLong);
        assertEq(longTradingExpo, 1000 ether, "longTradingExpo");
        uint256 numeratorSquared = uint256((longTradingExpo - int256(s.balanceVault)) ** 2);
        assertEq(numeratorSquared, 1000 ether ** 2, "numeratorSquared");
        uint256 denominator = s.balanceVault * s.balanceVault;
        int256 expectedFundingPerDay = -int256(
            numeratorSquared * s.fundingSF * 10 ** (Constants.FUNDING_RATE_DECIMALS - Constants.FUNDING_SF_DECIMALS)
                / denominator
        ) + EMA;
        assertLt(expectedFundingPerDay, 0, "negative funding");
        int256 expectedFunding = expectedFundingPerDay * int256(uint256(TIME_ELAPSED)) / 1 days;

        (int256 funding, int256 fundingPerDay, int256 longExpo) =
            protocol.i_funding(s, s.lastUpdateTimestamp + TIME_ELAPSED, EMA);
        assertEq(funding, expectedFunding, "funding");
        assertEq(fundingPerDay, expectedFundingPerDay, "funding rate");
        assertEq(longExpo, longTradingExpo, "longExpo");
    }

    /**
     * @custom:scenario Funding calculation when long exposure is equal to vault exposure
     * @custom:given The long trading expo is equal to the vault trading expo
     * @custom:and Some time has passed since the last update
     * @custom:when The funding is calculated
     * @custom:then The funding rate is equal to the EMA
     * @custom:and The funding is equal to the EMA multiplied by the elapsed time and divided by 86400
     * @custom:and The long exposure is as expected
     */
    function test_fundingEquilibrium() public {
        s.totalExpo = 2000 ether;
        s.balanceLong = 1000 ether;
        s.balanceVault = 1000 ether;

        int256 longTradingExpo = int256(s.totalExpo - s.balanceLong);
        assertEq(longTradingExpo, 1000 ether, "longTradingExpo");
        uint256 numeratorSquared = uint256((longTradingExpo - int256(s.balanceVault)) ** 2);
        assertEq(numeratorSquared, 0, "numeratorSquared");

        (int256 funding, int256 fundingPerDay, int256 longExpo) =
            protocol.i_funding(s, s.lastUpdateTimestamp + TIME_ELAPSED, EMA);
        assertEq(funding, EMA * int256(uint256(TIME_ELAPSED)) / 1 days, "funding");
        assertEq(fundingPerDay, EMA, "funding rate");
        assertEq(longExpo, longTradingExpo, "longExpo");
    }

    /**
     * @custom:scenario Funding calculation when vault exposure is zero
     * @custom:given The vault trading expo is zero
     * @custom:and Some time has passed since the last update
     * @custom:when The funding is calculated
     * @custom:then The funding is positive and as expected
     */
    function test_fundingPositiveZeroVault() public {
        s.totalExpo = 2000 ether;
        s.balanceLong = 1000 ether;
        s.balanceVault = 0;

        int256 longTradingExpo = int256(s.totalExpo - s.balanceLong);
        int256 expectedFundingPerDay =
            int256(s.fundingSF * 10 ** (Constants.FUNDING_RATE_DECIMALS - Constants.FUNDING_SF_DECIMALS)) + EMA;
        assertGt(expectedFundingPerDay, 0, "positive funding rate");
        int256 expectedFunding = expectedFundingPerDay * int256(uint256(TIME_ELAPSED)) / 1 days;

        (int256 funding, int256 fundingPerDay, int256 longExpo) =
            protocol.i_funding(s, s.lastUpdateTimestamp + TIME_ELAPSED, EMA);
        assertEq(funding, expectedFunding, "funding");
        assertEq(fundingPerDay, expectedFundingPerDay, "funding rate");
        assertEq(longExpo, longTradingExpo, "longExpo");
    }

    /**
     * @custom:scenario Funding calculation when long exposure is zero
     * @custom:given The long trading expo is zero
     * @custom:and Some time has passed since the last update
     * @custom:when The funding is calculated
     * @custom:then The funding is negative and as expected
     */
    function test_fundingNegativeZeroLong() public {
        s.totalExpo = 2000 ether;
        s.balanceLong = 2000 ether;
        s.balanceVault = 1000 ether;

        int256 longTradingExpo = int256(s.totalExpo - s.balanceLong);
        assertEq(longTradingExpo, 0, "longTradingExpo");
        int256 expectedFundingPerDay =
            -int256(s.fundingSF * 10 ** (Constants.FUNDING_RATE_DECIMALS - Constants.FUNDING_SF_DECIMALS)) + EMA;
        assertLt(expectedFundingPerDay, 0, "negative funding rate");
        int256 expectedFunding = expectedFundingPerDay * int256(uint256(TIME_ELAPSED)) / 1 days;

        (int256 funding, int256 fundingPerDay, int256 longExpo) =
            protocol.i_funding(s, s.lastUpdateTimestamp + TIME_ELAPSED, EMA);
        assertEq(funding, expectedFunding, "funding");
        assertEq(fundingPerDay, expectedFundingPerDay, "funding rate");
        assertEq(longExpo, longTradingExpo, "longExpo");
    }

    /**
     * @custom:scenario Check the funding rate is proportional to the imbalance squared (positive imbalance)
     * @custom:given An imbalance of +50% (more in the long side)
     * @custom:or an imbalance of 25%
     * @custom:when The imbalance is halved
     * @custom:then The funding rate is 4 times smaller
     */
    function test_fundingVsImbalancePos() public {
        // long trading expo = 1000 ether
        s.totalExpo = 2000 ether;
        s.balanceLong = 1000 ether;
        // vault trading expo = 500 ether
        s.balanceVault = 500 ether;

        int256 longTradingExpo = int256(s.totalExpo - s.balanceLong);
        // imbalance = (longExpo - vaultExpo) / max(longExpo, vaultExpo) = (longExpo - vaultExpo) / longExpo
        // represented here with 18 decimals for the purpose of this test
        int256 imbalance = (longTradingExpo - int256(s.balanceVault)) * 1 ether / longTradingExpo;
        assertEq(imbalance, 0.5 ether, "imbalance A");

        // funding should be proportional to the imbalance squared
        (, int256 fundingPerDayA,) = protocol.i_funding(s, s.lastUpdateTimestamp + TIME_ELAPSED, 0);

        // halve the imbalance
        s.balanceVault = 750 ether;
        imbalance = (longTradingExpo - int256(s.balanceVault)) * 1 ether / longTradingExpo;
        assertEq(imbalance, 0.25 ether, "imbalance B");
        (, int256 fundingPerDayB,) = protocol.i_funding(s, s.lastUpdateTimestamp + TIME_ELAPSED, 0);

        // the funding is divided by 4
        assertEq(fundingPerDayB, fundingPerDayA / 4, "funding rate A vs B");
    }

    /**
     * @custom:scenario Check the funding rate is proportional to the imbalance squared (negative imbalance)
     * @custom:given An imbalance of -50% (more in the vault side)
     * @custom:or an imbalance of -25%
     * @custom:when The imbalance is halved
     * @custom:then The funding rate (absolute value) is 4 times smaller
     */
    function test_fundingVsImbalanceNeg() public {
        // long trading expo = 500 ether
        s.totalExpo = 2000 ether;
        s.balanceLong = 1500 ether;
        // vault trading expo = 1000 ether
        s.balanceVault = 1000 ether;

        int256 longTradingExpo = int256(s.totalExpo - s.balanceLong);
        // imbalance = (longExpo - vaultExpo) / max(longExpo, vaultExpo) = (longExpo - vaultExpo) / vaultExpo
        // represented here with 18 decimals for the purpose of this test
        int256 imbalance = (longTradingExpo - int256(s.balanceVault)) * 1 ether / int256(s.balanceVault);
        assertEq(imbalance, -0.5 ether, "imbalance A");

        // funding should be proportional to the imbalance squared
        (, int256 fundingPerDayA,) = protocol.i_funding(s, s.lastUpdateTimestamp + TIME_ELAPSED, 0);

        // halve the imbalance
        s.balanceLong = 1250 ether;
        longTradingExpo = int256(s.totalExpo - s.balanceLong);
        imbalance = (longTradingExpo - int256(s.balanceVault)) * 1 ether / int256(s.balanceVault);
        assertEq(imbalance, -0.25 ether, "imbalance B");
        (, int256 fundingPerDayB,) = protocol.i_funding(s, s.lastUpdateTimestamp + TIME_ELAPSED, 0);

        // the funding is divided by 4
        assertEq(fundingPerDayB, fundingPerDayA / 4, "funding rate A vs B");
    }

    /**
     * @custom:scenario Check the funding rate is proportional to the funding scaling factor
     * @custom:given A funding scaling factor between 0 and 1
     * @custom:and a total exposure between 1 ether and 1.2e9 ether
     * @custom:and a long balance between 0 and the total exposure
     * @custom:and a vault balance between 0 and 120e6 ether
     * @custom:and an EMA between in the appropriate range
     * @custom:when The funding scaling factor is doubled
     * @custom:then The funding rate is doubled
     * @custom:when The EMA is passed to the funding calculation
     * @custom:then The funding rate has the EMA added to it
     */
    function testFuzz_fundingVsScalingFactorAndEMA(
        uint256 sf,
        uint256 totalExpo,
        uint256 balanceLong,
        uint256 balanceVault,
        int256 ema
    ) public {
        s.fundingSF = bound(sf, 0, 10 ** protocol.FUNDING_SF_DECIMALS());
        // as a safe upper bound, we use the total supply of eth with a leverage max of 10x
        s.totalExpo = bound(totalExpo, 1 ether, 1.2e9 ether);
        s.balanceLong = bound(balanceLong, 0, s.totalExpo);
        s.balanceVault = bound(balanceVault, 0, 120e6 ether);

        // funding should be proportional to fundingSF
        (int256 fundingA, int256 fundingPerDayA,) = protocol.i_funding(s, s.lastUpdateTimestamp + TIME_ELAPSED, 0);

        // double the scaling factor
        s.fundingSF = 2 * s.fundingSF;

        (int256 fundingB, int256 fundingPerDayB,) = protocol.i_funding(s, s.lastUpdateTimestamp + TIME_ELAPSED, 0);

        // the funding rate should double (with 1 wei tolerance)
        assertApproxEqAbs(fundingPerDayB, fundingPerDayA * 2, 1, "funding rate A vs B");
        assertApproxEqAbs(fundingB, fundingA * 2, 2, "funding A vs B");

        // since we cap the imbalance to 100%, the funding rate (without EMA contribution) is at most:
        int256 fundingPerDayMax =
            int256(s.fundingSF * 10 ** (protocol.FUNDING_RATE_DECIMALS() - protocol.FUNDING_SF_DECIMALS()));
        // a good upper bound for the EMA is thus:
        int256 emaMax = 2 * fundingPerDayMax;
        // we bound the EMA by this value
        ema = bound(ema, -emaMax, emaMax);

        // EMA is added to the new value of the funding
        (int256 fundingC, int256 fundingPerDayC,) = protocol.i_funding(s, s.lastUpdateTimestamp + TIME_ELAPSED, ema);

        assertEq(fundingPerDayC, fundingPerDayB + ema, "funding rate B vs C");
        assertEq(fundingC, (fundingPerDayB + ema) * int256(uint256(TIME_ELAPSED)) / 1 days, "funding B vs C");
    }

    /**
     * @custom:scenario Revert with a past timestamp
     * @custom:when The funding is calculated with a timestamp prior to the last update timestamp
     * @custom:then The transaction reverts with `UsdnProtocolTimestampTooOld`
     */
    function test_RevertWhen_fundingWithPastTimestamp() public {
        vm.expectRevert(UsdnProtocolTimestampTooOld.selector);
        protocol.i_funding(s, s.lastUpdateTimestamp - 1, EMA);
    }
}

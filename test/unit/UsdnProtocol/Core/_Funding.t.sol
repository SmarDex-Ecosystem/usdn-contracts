// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import { UsdnProtocolBaseFixture } from "../utils/Fixtures.sol";
import { UsdnProtocolHandler } from "../utils/Handler.sol";

import { UsdnProtocolConstantsLibrary as Constants } from
    "../../../../src/UsdnProtocol/libraries/UsdnProtocolConstantsLibrary.sol";

contract TestUsdnProtocolCoreFunding is UsdnProtocolBaseFixture {
    UsdnProtocolHandler.FundingStorage s;
    int256 constant EMA = int256(3 * 10 ** (Constants.FUNDING_RATE_DECIMALS - 4));

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

    function test_fundingNoTimeElapsed() public {
        (int256 fund, int256 longExpo) = protocol.i_funding(s, s.lastUpdateTimestamp, EMA);
        assertEq(fund, 0, "funding");
        assertEq(longExpo, int256(s.totalExpo - s.balanceLong), "longExpo");
    }

    function test_fundingTimeElapsedPositive() public {
        s.totalExpo = 2000 ether;
        s.balanceLong = 1000 ether;
        s.balanceVault = 500 ether;
        uint128 timeElapsed = 100;

        int256 longTradingExpo = int256(s.totalExpo - s.balanceLong);
        assertEq(longTradingExpo, 1000 ether, "longTradingExpo");
        uint256 numeratorSquared = uint256((longTradingExpo - int256(s.balanceVault)) ** 2);
        assertEq(numeratorSquared, 500 ether ** 2, "numeratorSquared");
        uint256 denominator = uint256(longTradingExpo * longTradingExpo) * 1 days;
        int256 expectedFunding = int256(
            numeratorSquared * timeElapsed * s.fundingSF
                * 10 ** (Constants.FUNDING_RATE_DECIMALS - Constants.FUNDING_SF_DECIMALS) / denominator
        ) + EMA;

        (int256 fund, int256 longExpo) = protocol.i_funding(s, s.lastUpdateTimestamp + timeElapsed, EMA);
        assertEq(fund, expectedFunding, "funding");
        assertEq(longExpo, longTradingExpo, "longExpo");
    }

    function test_fundingTimeElapsedNegative() public {
        s.totalExpo = 2000 ether;
        s.balanceLong = 1000 ether;
        s.balanceVault = 1500 ether;
        uint128 timeElapsed = 100;

        int256 longTradingExpo = int256(s.totalExpo - s.balanceLong);
        assertEq(longTradingExpo, 1000 ether, "longTradingExpo");
        uint256 numeratorSquared = uint256((longTradingExpo - int256(s.balanceVault)) ** 2);
        assertEq(numeratorSquared, 500 ether ** 2, "numeratorSquared");
        uint256 denominator = s.balanceVault * s.balanceVault * 1 days;
        int256 expectedFunding = -int256(
            numeratorSquared * timeElapsed * s.fundingSF
                * 10 ** (Constants.FUNDING_RATE_DECIMALS - Constants.FUNDING_SF_DECIMALS) / denominator
        ) + EMA;

        (int256 fund, int256 longExpo) = protocol.i_funding(s, s.lastUpdateTimestamp + timeElapsed, EMA);
        assertEq(fund, expectedFunding, "funding");
        assertEq(longExpo, longTradingExpo, "longExpo");
    }

    function test_fundingEquilibrium() public {
        s.totalExpo = 2000 ether;
        s.balanceLong = 1000 ether;
        s.balanceVault = 1000 ether;
        uint128 timeElapsed = 100;

        int256 longTradingExpo = int256(s.totalExpo - s.balanceLong);
        assertEq(longTradingExpo, 1000 ether, "longTradingExpo");
        uint256 numeratorSquared = uint256((longTradingExpo - int256(s.balanceVault)) ** 2);
        assertEq(numeratorSquared, 0, "numeratorSquared");

        (int256 fund, int256 longExpo) = protocol.i_funding(s, s.lastUpdateTimestamp + timeElapsed, EMA);
        assertEq(fund, EMA, "funding");
        assertEq(longExpo, longTradingExpo, "longExpo");
    }

    function test_fundingPositiveZeroVault() public {
        s.totalExpo = 2000 ether;
        s.balanceLong = 1000 ether;
        s.balanceVault = 0;
        uint128 timeElapsed = 100;

        int256 longTradingExpo = int256(s.totalExpo - s.balanceLong);
        int256 expectedFunding =
            int256(s.fundingSF * 10 ** (Constants.FUNDING_RATE_DECIMALS - Constants.FUNDING_SF_DECIMALS)) + EMA;

        (int256 fund, int256 longExpo) = protocol.i_funding(s, s.lastUpdateTimestamp + timeElapsed, EMA);
        assertEq(fund, expectedFunding, "funding");
        assertEq(longExpo, longTradingExpo, "longExpo");
    }

    function test_fundingNegativeZeroLong() public {
        s.totalExpo = 2000 ether;
        s.balanceLong = 2000 ether;
        s.balanceVault = 1000 ether;
        uint128 timeElapsed = 100;

        int256 longTradingExpo = int256(s.totalExpo - s.balanceLong);
        assertEq(longTradingExpo, 0, "longTradingExpo");
        int256 expectedFunding =
            -int256(s.fundingSF * 10 ** (Constants.FUNDING_RATE_DECIMALS - Constants.FUNDING_SF_DECIMALS)) + EMA;

        (int256 fund, int256 longExpo) = protocol.i_funding(s, s.lastUpdateTimestamp + timeElapsed, EMA);
        assertEq(fund, expectedFunding, "funding");
        assertEq(longExpo, longTradingExpo, "longExpo");
    }

    function test_RevertWhen_fundingWithPastTimestamp() public {
        vm.expectRevert(UsdnProtocolTimestampTooOld.selector);
        protocol.i_funding(s, s.lastUpdateTimestamp - 1, EMA);
    }
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { UsdnProtocolBaseFixture } from "../utils/Fixtures.sol";

/**
 * @custom:feature tests for the _calcMaxLongBalance function
 * @custom:background Given a protocol instance that was initialized with default params
 */
contract TestUsdnProtocolCalcMaxLongBalance is UsdnProtocolBaseFixture {
    function setUp() public {
        super._setUp(DEFAULT_PARAMS);
    }

    /**
     * @custom:scenario Check the results of _calcMaxLongBalance depending on the provided total expo
     * @custom:when _calcMaxLongBalance is called with a total expo
     * @custom:when The returned value is the sum of the min trading expo and the max long balance (+/- 1)
     * @custom:when _calcMaxLongBalance is called with 0
     * @custom:when The returned value is 0
     */
    function test_calcMaxLongBalance() public view {
        uint256 marginBps = protocol.MIN_LONG_TRADING_EXPO_BPS();

        uint256 totalExpo = 100 ether;
        uint256 minTradingExpo = totalExpo * protocol.MIN_LONG_TRADING_EXPO_BPS() / BPS_DIVISOR;
        uint256 maxLongBalance = protocol.i_calcMaxLongBalance(totalExpo);
        assertEq(
            maxLongBalance + minTradingExpo,
            totalExpo,
            "the sum of the max long balance and min trading expo should be equal to the total expo"
        );

        totalExpo = uint256(type(int256).max) / 10_000;
        minTradingExpo = totalExpo * protocol.MIN_LONG_TRADING_EXPO_BPS() / BPS_DIVISOR;
        maxLongBalance = protocol.i_calcMaxLongBalance(totalExpo);
        assertEq(
            maxLongBalance + minTradingExpo + 1, // +1 because of lack of precision
            totalExpo,
            "the sum of the max long balance and min trading expo should be equal to the total expo"
        );

        totalExpo = 0;
        maxLongBalance = protocol.i_calcMaxLongBalance(totalExpo);
        assertEq(maxLongBalance, 0, "the max long balance should be equal to 0");

        totalExpo = 1;
        maxLongBalance = protocol.i_calcMaxLongBalance(totalExpo);
        assertEq(maxLongBalance, 0, "the max long balance should be equal to 0");
    }

    /**
     * @custom:scenario Make sure the sum of the max long balance and the min trading expo is always equal to the
     * provided total expo
     * @custom:when _calcMaxLongBalance is called with a total expo
     * @custom:when The returned value is the sum of the min trading expo and the max long balance (+/- 1)
     * @param totalExpo The total expo to calculate the max long balance
     */
    function testFuzz_calcMaxLongBalance(uint256 totalExpo) public view {
        totalExpo = bound(totalExpo, 0, uint256(type(int256).max) / 10_000);

        uint256 minTradingExpo = totalExpo * protocol.MIN_LONG_TRADING_EXPO_BPS() / BPS_DIVISOR;
        uint256 maxLongBalance = protocol.i_calcMaxLongBalance(totalExpo);

        assertApproxEqAbs(
            minTradingExpo + maxLongBalance,
            totalExpo,
            1,
            "The sum of the max long balance and the min trading expo should equal the trading expo"
        );
    }
}

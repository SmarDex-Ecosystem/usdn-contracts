// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { UsdnProtocolBaseFixture } from "../utils/Fixtures.sol";

/**
 * @custom:feature Test the {_calcImbalanceCloseBps} internal function of the long layer
 * @custom:background An initialized usdn protocol contract with default parameters
 */
contract TestUsdnProtocolLongCalcImbalanceCloseBps is UsdnProtocolBaseFixture {
    function setUp() public {
        super._setUp(DEFAULT_PARAMS);
    }

    /**
     * @custom:scenario Calculate the imbalance with no trading expo
     * @custom:when The vault balance is 200 ether
     * @custom:and The long balance and total expo are at 0
     * @custom:then The imbalance is infinite
     * @custom:then int256.max is returned
     */
    function test_calcImbalanceCloseBpsWith0TradingExpo() public view {
        int256 vaultBalance = 200 ether;
        int256 longBalance = 0;
        uint256 totalExpo = 0;
        int256 imbalanceBps = protocol.i_calcImbalanceCloseBps(vaultBalance, longBalance, totalExpo);
        assertEq(imbalanceBps, type(int256).max, "The imbalance should be infinite (int256.max)");
    }

    /**
     * @custom:scenario Calculate the imbalance with different values
     * @custom:when The vault balance is 200 ether
     * @custom:and The long balance is 100 ether
     * @custom:and The total expo is 300 ether
     * @custom:then The imbalance is 0
     * @custom:or The total expo is 250 ether
     * @custom:then The imbalance is 33.33%
     * @custom:or The total expo is 400 ether
     * @custom:then The imbalance is -33.33%
     */
    function test_calcImbalanceCloseBps() public view {
        int256 vaultBalance = 200 ether;
        int256 longBalance = 100 ether;
        uint256 totalExpo = 300 ether;
        int256 imbalanceBps = protocol.i_calcImbalanceCloseBps(vaultBalance, longBalance, totalExpo);
        assertEq(imbalanceBps, 0, "The imbalance should be 0");

        totalExpo = 250 ether;
        imbalanceBps = protocol.i_calcImbalanceCloseBps(vaultBalance, longBalance, totalExpo);
        assertEq(imbalanceBps, int256(BPS_DIVISOR / 3), "The imbalance should be 33.33%");

        totalExpo = 400 ether;
        imbalanceBps = protocol.i_calcImbalanceCloseBps(vaultBalance, longBalance, totalExpo);
        assertEq(imbalanceBps, -int256(BPS_DIVISOR / 3), "The imbalance should be -33%");
    }

    /**
     * @custom:scenario Calculate the imbalance with different values
     * @custom:when The vault balance is between 0 and int256.max / BPS_DIVISOR
     * @custom:and The long balance is between 0 and (int256.max / BPS_DIVISOR) - 1
     * @custom:and The total expo is between the long balance + 1 and int256.max / BPS_DIVISOR
     * @custom:then The returned imbalance is equal to the expected one
     * @param vaultBalance The vault balance
     * @param longBalance The long balance
     * @param totalExpo The total expo
     */
    function testFuzz_calcImbalanceCloseBps(uint256 vaultBalance, uint256 longBalance, uint256 totalExpo) public view {
        vaultBalance = bound(vaultBalance, 0, uint256(type(int256).max) / BPS_DIVISOR);
        longBalance = bound(longBalance, 0, uint256(type(int256).max) / BPS_DIVISOR - 1);
        totalExpo = bound(totalExpo, longBalance + 1, uint256(type(int256).max) / BPS_DIVISOR);

        int256 expectedImbalance = (int256(vaultBalance) - int256(totalExpo - longBalance)) * int256(BPS_DIVISOR)
            / int256(totalExpo - longBalance);

        int256 imbalanceBps = protocol.i_calcImbalanceCloseBps(int256(vaultBalance), int256(longBalance), totalExpo);
        assertEq(imbalanceBps, expectedImbalance, "The imbalance should be equal to the expected one");
    }
}

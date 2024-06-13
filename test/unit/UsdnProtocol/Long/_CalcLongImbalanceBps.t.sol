// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import { UsdnProtocolBaseFixture } from "../utils/Fixtures.sol";

/**
 * @custom:feature Test the {_calcLongImbalanceBps} internal function of the long layer
 * @custom:background An initialized usdn protocol contract with default parameters
 */
contract TestUsdnProtocolLongCalcLongImbalanceBps is UsdnProtocolBaseFixture {
    function setUp() public {
        super._setUp(DEFAULT_PARAMS);
    }

    /**
     * @custom:scenario Calculate the long imbalance with different values
     * @custom:when The vault balance is 200 ether
     * @custom:and The long balance is 100 ether
     * @custom:and The total expo is 300 ether
     * @custom:then The imbalance is 0
     * @custom:or The total expo is 200 ether
     * @custom:then The imbalance is 50%
     * @custom:or The total expo is 400 ether
     * @custom:then The imbalance is -50%
     */
    function test_calcLongImbalanceBps() public {
        uint256 vaultBalance = 200 ether;
        uint256 longBalance = 100 ether;
        uint256 totalExpo = 300 ether;
        int256 imbalanceBps = protocol.i_calcLongImbalanceBps(vaultBalance, longBalance, totalExpo);
        assertEq(imbalanceBps, 0, "The imbalance should be 0");

        totalExpo = 200 ether;
        imbalanceBps = protocol.i_calcLongImbalanceBps(vaultBalance, longBalance, totalExpo);
        assertEq(imbalanceBps, int256(BPS_DIVISOR / 2), "The imbalance should be 50%");

        totalExpo = 400 ether;
        imbalanceBps = protocol.i_calcLongImbalanceBps(vaultBalance, longBalance, totalExpo);
        assertEq(imbalanceBps, -int256(BPS_DIVISOR / 2), "The imbalance should be -50%");
    }

    /**
     * @custom:scenario Calculate the long imbalance with different values
     * @custom:when The vault balance is between 1 and int256.max / BPS_DIVISOR
     * @custom:and The long balance is between 0 and int256.max / BPS_DIVISOR
     * @custom:and The total expo is between the long balance and int256.max / BPS_DIVISOR
     * @param vaultBalance The vault balance
     * @param longBalance The long balance
     * @param totalExpo The total expo
     */
    function testFuzz_calcLongImbalanceBps(uint256 vaultBalance, uint256 longBalance, uint256 totalExpo) public {
        vaultBalance = bound(vaultBalance, 1, uint256(type(int256).max) / BPS_DIVISOR);
        longBalance = bound(longBalance, 0, uint256(type(int256).max) / BPS_DIVISOR);
        totalExpo = bound(totalExpo, longBalance, uint256(type(int256).max) / BPS_DIVISOR);

        int256 expectedImbalance =
            (int256(vaultBalance) - int256(totalExpo - longBalance)) * int256(BPS_DIVISOR) / int256(vaultBalance);

        int256 imbalanceBps = protocol.i_calcLongImbalanceBps(vaultBalance, longBalance, totalExpo);
        assertEq(imbalanceBps, expectedImbalance, "The imbalance should be equal to the expected one");
    }
}

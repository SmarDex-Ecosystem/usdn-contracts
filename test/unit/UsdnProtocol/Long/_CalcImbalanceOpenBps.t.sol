// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { IUsdnProtocolErrors } from "../../../../src/interfaces/UsdnProtocol/IUsdnProtocolErrors.sol";
import { UsdnProtocolBaseFixture } from "../utils/Fixtures.sol";

/**
 * @custom:feature Test the {_calcImbalanceOpenBps} internal function of the long layer
 * @custom:background An initialized usdn protocol contract with default parameters
 */
contract TestUsdnProtocolLongCalcImbalanceOpenBps is UsdnProtocolBaseFixture {
    function setUp() public {
        super._setUp(DEFAULT_PARAMS);
    }

    /**
     * @custom:scenario Calculate the imbalance with no trading expo
     * @custom:when The vault balance is 0
     * @custom:and The long balance is 100 ether
     * @custom:and The total expo is 200 ether
     * @custom:then The imbalance is infinite
     * @custom:and int256.max is returned
     */
    function test_calcImbalanceOpenBpsWith0VaultBalance() public {
        int256 vaultBalance = 0;
        int256 longBalance = 100 ether;
        uint256 totalExpo = 200 ether;
        vm.expectRevert(IUsdnProtocolErrors.UsdnProtocolEmptyVault.selector);
        protocol.i_calcImbalanceOpenBps(vaultBalance, longBalance, totalExpo);
    }

    /**
     * @custom:scenario Calculate the imbalance with different values
     * @custom:given The long balance is 100 ether
     * @custom:and The total expo is 300 ether
     * @custom:when The vault balance is 200 ether
     * @custom:then The imbalance is 0
     * @custom:when The vault balance is 133.33 ether
     * @custom:then The imbalance is 50%
     * @custom:when The vault balance is 300 ether
     * @custom:then The imbalance is -50%
     */
    function test_calcImbalanceOpenBps() public view {
        int256 vaultBalance = 200 ether;
        int256 longBalance = 100 ether;
        uint256 totalExpo = 300 ether;
        int256 imbalanceBps = protocol.i_calcImbalanceOpenBps(vaultBalance, longBalance, totalExpo);
        assertEq(imbalanceBps, 0, "The imbalance should be 0");

        vaultBalance = 133_333_333_333_333_333_333;
        imbalanceBps = protocol.i_calcImbalanceOpenBps(vaultBalance, longBalance, totalExpo);
        assertEq(imbalanceBps, int256(BPS_DIVISOR / 2), "The imbalance should be 50%");

        vaultBalance = 400 ether;
        imbalanceBps = protocol.i_calcImbalanceOpenBps(vaultBalance, longBalance, totalExpo);
        assertEq(imbalanceBps, -int256(BPS_DIVISOR / 2), "The imbalance should be -50%");
    }

    /**
     * @custom:scenario Calculate the imbalance with different values
     * @custom:when The vault balance is between 1 and int256.max / BPS_DIVISOR
     * @custom:and The long balance is between 0 and int256.max / BPS_DIVISOR
     * @custom:and The total expo is between the long balance and int256.max / BPS_DIVISOR
     * @custom:then The returned imbalance is equal to the expected one
     * @param vaultBalance The vault balance
     * @param longBalance The long balance
     * @param totalExpo The total expo
     */
    function testFuzz_calcImbalanceOpenBps(uint256 vaultBalance, uint256 longBalance, uint256 totalExpo) public view {
        vaultBalance = bound(vaultBalance, 1, uint256(type(int256).max) / BPS_DIVISOR);
        longBalance = bound(longBalance, 0, uint256(type(int256).max) / BPS_DIVISOR);
        totalExpo = bound(totalExpo, longBalance, uint256(type(int256).max) / BPS_DIVISOR);

        int256 expectedImbalance =
            (int256(totalExpo - longBalance) - int256(vaultBalance)) * int256(BPS_DIVISOR) / int256(vaultBalance);

        int256 imbalanceBps = protocol.i_calcImbalanceOpenBps(int256(vaultBalance), int256(longBalance), totalExpo);
        assertEq(imbalanceBps, expectedImbalance, "The imbalance should be equal to the expected one");
    }
}

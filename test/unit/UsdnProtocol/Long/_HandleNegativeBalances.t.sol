// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { UsdnProtocolBaseFixture } from "../utils/Fixtures.sol";

/**
 * @custom:feature Test the {_handleNegativeBalances} internal function of the long layer
 * @custom:background An initialized usdn protocol contract with default parameters
 */
contract TestUsdnProtocolHandleNegativeBalances is UsdnProtocolBaseFixture {
    function setUp() public {
        super._setUp(DEFAULT_PARAMS);
    }

    /**
     * @custom:scenario Verify the clamping of the long balance
     * @custom:given A vault balance of -200 ether
     * @custom:and A long balance of 50 ether
     * @custom:when The {_handleNegativeBalances} function is called
     * @custom:then The new long balance is 0
     */
    function test_longBalanceShouldBe0() public view {
        int256 vaultBalance = -200 ether;
        int256 longBalance = 50 ether;
        (uint256 longBalance_,) = protocol.i_handleNegativeBalances(vaultBalance, longBalance);
        assertEq(longBalance_, 0, "Long balance should be clamped 0");
    }
}

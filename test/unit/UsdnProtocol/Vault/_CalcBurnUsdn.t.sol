// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { UsdnProtocolBaseFixture } from "../utils/Fixtures.sol";

/**
 * @custom:feature The _calcBurnUsdn internal function of the UsdnProtocolVault contract.
 * @custom:background Given a protocol instance that was initialized with default params
 */
contract TestUsdnProtocolVaultCalcBurnUsdn is UsdnProtocolBaseFixture {
    function setUp() public {
        super._setUp(DEFAULT_PARAMS);
    }

    /**
     * @custom:scenario Check calculation asset received when withdrawing
     * @custom:given A protocol initialized with default params
     * @custom:when The function "_calcBurnUsdn" is called with some parameters
     * @custom:then The asset amount is calculated correctly
     */
    function test_calcBurnUsdn() public view {
        uint256 usdnShares = 10 ether;
        uint256 available = 10 ether;
        uint256 usdnTotalShares = 10 ether;
        uint256 assetExpected = protocol.i_calcBurnUsdn(usdnShares, available, usdnTotalShares);
        assertEq(assetExpected, 10 ether, "assetExpected must match with expected value (10 ether)");

        usdnShares = 100;
        available = 6 ether;
        usdnTotalShares = 500;
        assetExpected = protocol.i_calcBurnUsdn(usdnShares, available, usdnTotalShares);
        assertEq(assetExpected, 12e17, "assetExpected must match with expected value (12e17)");

        usdnShares = 6000 ether;
        available = 1 ether;
        usdnTotalShares = 2 ether;
        assetExpected = protocol.i_calcBurnUsdn(usdnShares, available, usdnTotalShares);
        assertEq(assetExpected, 3e21, "assetExpected must match with expected value (3e21)");
    }
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { UsdnProtocolBaseFixture } from "test/unit/UsdnProtocol/utils/Fixtures.sol";

import { ProtocolAction } from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";

/**
 * @custom:feature The _calcBurnUsdn internal function of the UsdnProtocolVault contract.
 * @custom:background Given a protocol instance that was initialized with default params
 * @custom:and A user who deposited 1 wstETH at price $2000 to get 2000 USDN
 */
contract TestUsdnProtocolVaultCalcBurnUsdn is UsdnProtocolBaseFixture {
    function setUp() public {
        super._setUp(DEFAULT_PARAMS);
        usdn.approve(address(protocol), type(uint256).max);
    }

    /**
     * @custom:scenario Check calculation asset received when withdraw
     * @custom:given A protocol initialized with default params
     * @custom:when The function "_calcBurnUsdn" is called with some parameters
     * @custom:then The total supply is calculated correctly
     */
    function test_calcBurnUsdn() public {
        uint256 usdnShares = 10 ether;
        uint256 available = 10 ether;
        uint256 usdnTotalShares = 10 ether;
        uint256 assetExpected = protocol.i_calcBurnUsdn(usdnShares, available, usdnTotalShares);
        assertEq(assetExpected, 10_000_000_000_000_000_000, "assetExpected must match with expected value");

        usdnShares = 787 ether;
        available = 28 ether;
        usdnTotalShares = 79_680_003;
        assetExpected = protocol.i_calcBurnUsdn(usdnShares, available, usdnTotalShares);
        assertEq(
            assetExpected, 276_556_214_487_090_318_006_137_625_270_922, "assetExpected must match with expected value"
        );
        usdnShares = 79 ether;
        available = 8962 ether;
        usdnTotalShares = 248_325 ether;
        assetExpected = protocol.i_calcBurnUsdn(usdnShares, available, usdnTotalShares);
        assertEq(assetExpected, 2_851_094_332_024_564_582, "assetExpected must match with expected value");
    }
}

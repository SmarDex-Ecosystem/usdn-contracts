// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { UsdnProtocolBaseFixture } from "test/unit/UsdnProtocol/utils/Fixtures.sol";

/**
 * @custom:feature The _calcRebaseTotalSupply internal function of the UsdnProtocolVault contract.
 * @custom:background Given a protocol instance that was initialized with default params
 */
contract TestUsdnProtocolCalcRebaseTotalSupply is UsdnProtocolBaseFixture {
    function setUp() public {
        super._setUp(DEFAULT_PARAMS);
    }

    /**
     * @custom:scenario Check calculation the required USDN total supply to reach `targetPrice`
     */
    function test_calcRebaseTotalSupply() public {
        uint256 vaultBalance = 1000;
        uint128 assetPrice = 1000;
        uint128 targetPrice = 500;
        uint8 assetDecimals = 18;
        uint256 totalSupply = protocol.i_calcRebaseTotalSupply(vaultBalance, assetPrice, targetPrice, assetDecimals);
        assertEq(totalSupply, 2000, "totalSupply must match with expected value");

        vaultBalance = 524_896;
        assetPrice = 7_868_645;
        targetPrice = 48;
        assetDecimals = 2;
        totalSupply = protocol.i_calcRebaseTotalSupply(vaultBalance, assetPrice, targetPrice, assetDecimals);
        assertEq(totalSupply, 860_462_559_566_666_666_666_666_666, "totalSupply must match with expected value");

        vaultBalance = 58_734;
        assetPrice = 58_926_485_247;
        targetPrice = 5_784_625;
        assetDecimals = 23;
        totalSupply = protocol.i_calcRebaseTotalSupply(vaultBalance, assetPrice, targetPrice, assetDecimals);
        assertEq(totalSupply, 5983, "totalSupply must match with expected value");

        vaultBalance = 1;
        assetPrice = 20;
        targetPrice = 20;
        assetDecimals = 19;
        totalSupply = protocol.i_calcRebaseTotalSupply(vaultBalance, assetPrice, targetPrice, assetDecimals);
        assertEq(totalSupply, 0, "totalSupply must match with expected value");

        vaultBalance = 1;
        assetPrice = 15;
        targetPrice = 10;
        assetDecimals = 45;
        totalSupply = protocol.i_calcRebaseTotalSupply(vaultBalance, assetPrice, targetPrice, assetDecimals);
        assertEq(totalSupply, 0, "totalSupply must match with expected value");
    }
}

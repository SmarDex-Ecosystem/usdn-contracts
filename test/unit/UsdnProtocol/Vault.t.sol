// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { UsdnProtocolBaseFixture } from "test/unit/UsdnProtocol/utils/Fixtures.sol";

/**
 * @custom:feature Test the functions in the vault contract
 * @custom:background Given a protocol instance that was initialized with default params
 */
contract TestUsdnProtocolVault is UsdnProtocolBaseFixture {
    function setUp() public {
        super._setUp(DEFAULT_PARAMS);
    }

    /**
     * @custom:scenario Check calculation of USDN price
     * @custom:given The USDN token has 18 decimals
     * @custom:and The asset token has 6 decimals
     * @custom:and The vault has 1000 tokens or 1100 tokens or 900 tokens
     * @custom:and The price of the asset is $2000 or $1000
     * @custom:and The total supply of USDN is 2M or 1M
     * @custom:when We call `_calcUsdnPrice`
     * @custom:then The price is $1 or $1.1 or $0.9 or $0.5 or $2
     */
    function test_calcUsdnPrice() public {
        uint8 usdnDecimals = 18;
        uint8 assetDecimals = 6;
        // 1000 tokens in vault
        uint256 vaultBalance = 1000 * 10 ** assetDecimals;
        // at price of $2000
        uint128 assetPrice = 2000 ether;
        // mint at price of $1 = 1000 tokens * $2000 = 2M
        uint128 usdnTotalSupply = uint128(2e6 * 10 ** usdnDecimals);
        uint256 price = protocol.i_calcUsdnPrice(vaultBalance, assetPrice, usdnTotalSupply, usdnDecimals, assetDecimals);
        assertEq(price, 1 ether, "price at balance 1000");

        // if balance is greater
        vaultBalance = 1100 * 10 ** assetDecimals;
        price = protocol.i_calcUsdnPrice(vaultBalance, assetPrice, usdnTotalSupply, usdnDecimals, assetDecimals);
        assertEq(price, 1.1 ether, "price at balance 1100");

        // if balance is lower
        vaultBalance = 900 * 10 ** assetDecimals;
        price = protocol.i_calcUsdnPrice(vaultBalance, assetPrice, usdnTotalSupply, usdnDecimals, assetDecimals);
        assertEq(price, 0.9 ether, "price at balance 900");

        // price is $1000
        vaultBalance = 1000 * 10 ** assetDecimals;
        assetPrice = 1000 ether;
        price = protocol.i_calcUsdnPrice(vaultBalance, assetPrice, usdnTotalSupply, usdnDecimals, assetDecimals);
        assertEq(price, 0.5 ether, "price at asset price $1000");

        // total supply is 1M
        assetPrice = 2000 ether;
        usdnTotalSupply = uint128(1e6 * 10 ** usdnDecimals);
        price = protocol.i_calcUsdnPrice(vaultBalance, assetPrice, usdnTotalSupply, usdnDecimals, assetDecimals);
        assertEq(price, 2 ether, "price at total supply of 1M");
    }
}

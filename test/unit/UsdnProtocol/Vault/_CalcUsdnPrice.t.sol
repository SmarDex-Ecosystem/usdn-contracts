// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { UsdnProtocolBaseFixture } from "../utils/Fixtures.sol";

import { UsdnProtocolConstantsLibrary as Constants } from
    "../../../../src/UsdnProtocol/libraries/UsdnProtocolConstantsLibrary.sol";

/**
 * @custom:feature The _calcUsdnPrice internal function of the UsdnProtocolVault contract.
 * @custom:background Given a protocol instance that was initialized with default params
 */
contract TestUsdnProtocolCalcUsdnPrice is UsdnProtocolBaseFixture {
    function setUp() public {
        super._setUp(DEFAULT_PARAMS);
    }

    /**
     * @custom:scenario Check calculation of USDN price
     * @custom:given The USDN token has 18 decimals
     * @custom:and The asset token has 6 decimals
     * @custom:and The normal vault balance is 1000 tokens
     * @custom:and The normal asset price is $2000
     * @custom:and The normal total USDN supply is 2M
     * @custom:and The normal USDN price is $1
     * @custom:when The vault has 1000 tokens
     * @custom:then The price is $1
     * @custom:when The vault has 1100 tokens
     * @custom:then The price is $1.1
     * @custom:when The vault has 900 tokens
     * @custom:then The price is $0.9
     * @custom:when The price of the asset is $1000
     * @custom:then The price is $0.5
     * @custom:when The total supply of USDN is 1M
     * @custom:then The price is $2
     */
    function test_calcUsdnPrice() public view {
        uint8 assetDecimals = 6;
        // 1000 tokens in vault
        uint256 vaultBalance = 1000 * 10 ** assetDecimals;
        // at price of $2000
        uint128 assetPrice = 2000 ether;
        // mint at price of $1 = 1000 tokens * $2000 = 2M
        uint128 usdnTotalSupply = uint128(2e6 * 10 ** Constants.TOKENS_DECIMALS);
        uint256 price = protocol.i_calcUsdnPrice(vaultBalance, assetPrice, usdnTotalSupply, assetDecimals);
        assertEq(price, 1 ether, "price at balance 1000");

        // if balance is greater
        vaultBalance = 1100 * 10 ** assetDecimals;
        price = protocol.i_calcUsdnPrice(vaultBalance, assetPrice, usdnTotalSupply, assetDecimals);
        assertEq(price, 1.1 ether, "price at balance 1100");

        // if balance is lower
        vaultBalance = 900 * 10 ** assetDecimals;
        price = protocol.i_calcUsdnPrice(vaultBalance, assetPrice, usdnTotalSupply, assetDecimals);
        assertEq(price, 0.9 ether, "price at balance 900");

        // price is $1000
        vaultBalance = 1000 * 10 ** assetDecimals;
        assetPrice = 1000 ether;
        price = protocol.i_calcUsdnPrice(vaultBalance, assetPrice, usdnTotalSupply, assetDecimals);
        assertEq(price, 0.5 ether, "price at asset price $1000");

        // total supply is 1M
        assetPrice = 2000 ether;
        usdnTotalSupply = uint128(1e6 * 10 ** Constants.TOKENS_DECIMALS);
        price = protocol.i_calcUsdnPrice(vaultBalance, assetPrice, usdnTotalSupply, assetDecimals);
        assertEq(price, 2 ether, "price at total supply of 1M");
    }
}

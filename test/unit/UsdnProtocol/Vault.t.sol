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
    function test_calcUsdnPrice() public {
        uint8 assetDecimals = 6;
        // 1000 tokens in vault
        uint256 vaultBalance = 1000 * 10 ** assetDecimals;
        // at price of $2000
        uint128 assetPrice = 2000 ether;
        // mint at price of $1 = 1000 tokens * $2000 = 2M
        uint128 usdnTotalSupply = uint128(2e6 * 10 ** protocol.TOKENS_DECIMALS());
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
        usdnTotalSupply = uint128(1e6 * 10 ** protocol.TOKENS_DECIMALS());
        price = protocol.i_calcUsdnPrice(vaultBalance, assetPrice, usdnTotalSupply, assetDecimals);
        assertEq(price, 2 ether, "price at total supply of 1M");
    }

    /**
     * @custom:scenario Check the calculation the amount of SDEX tokens to burn depending on the amount of USDN
     * @custom:given An amount of USDN to be minted
     * @custom:when The function is called with this amount
     * @custom:then The correct amount of SDEX to burn is returned
     */
    function test_calcSdexToBurn() external {
        uint256 burnRatio = protocol.getSdexBurnOnDepositRatio();
        uint256 burnRatioDivisor = protocol.SDEX_BURN_ON_DEPOSIT_DIVISOR();
        uint8 usdnDecimals = protocol.TOKENS_DECIMALS();
        uint256 usdnToMint = 100 * 10 ** usdnDecimals;

        uint256 expectedSdexToBurn = usdnToMint * burnRatio / burnRatioDivisor;
        (uint256 sdexToBurn,) = protocol.i_calcSdexToBurn(usdnToMint);
        assertEq(sdexToBurn, expectedSdexToBurn, "Result does not match the expected value");

        usdnToMint = 1_582_309 * 10 ** (usdnDecimals - 2);
        expectedSdexToBurn = usdnToMint * burnRatio / burnRatioDivisor;
        (sdexToBurn,) = protocol.i_calcSdexToBurn(usdnToMint);
        assertEq(
            sdexToBurn,
            expectedSdexToBurn,
            "Result does not match expected value when the usdn to mint value is less round"
        );
    }
}

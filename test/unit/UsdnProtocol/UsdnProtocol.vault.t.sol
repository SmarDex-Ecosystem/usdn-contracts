// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { console2 } from "forge-std/console2.sol";

import { FixedPointMathLib } from "solady/src/utils/FixedPointMathLib.sol";

import { UsdnProtocolBaseFixture } from "test/unit/UsdnProtocol/utils/Fixtures.sol";

/**
 * @custom:feature The internal functions of the vault side of the protocol
 * @custom:background Given a protocol instance that was initialized
 */
contract TestUsdnProtocolVault is UsdnProtocolBaseFixture {
    function setUp() public override {
        super.setUp();
    }

    function test_usdnPriceUp() public {
        // right after initialization, the price is 1 USD
        assertEq(protocol.usdnPrice(INITIAL_PRICE, uint128(block.timestamp)), 1 ether, "usdn initial price");

        // simulate a profit for the long (ignoring funding rates)
        uint128 currentPrice = 2100 ether;

        // calculate the value of the init position of 1000 wei
        uint128 initLiqPrice = protocol.getEffectivePriceForTick(protocol.minTick());
        // expo is 1000 wei since leverage is almost 1
        uint256 initPosValue = 1000 * (currentPrice - initLiqPrice) / currentPrice;

        // calculate the value of the first long position
        uint128 liquidationPrice =
            protocol.getEffectivePriceForTick(protocol.getEffectiveTickForPrice(INITIAL_PRICE / 2));
        uint128 longInitialLeverage = protocol.getLeverage(INITIAL_PRICE, liquidationPrice);
        uint256 longExpo = uint256(INITIAL_LONG - protocol.FIRST_LONG_AMOUNT()) * longInitialLeverage
            / 10 ** protocol.LEVERAGE_DECIMALS();
        uint256 longPosValue = longExpo * (currentPrice - liquidationPrice) / currentPrice;

        // infer the vault balance from the long positions current value
        uint256 vaultBalance = INITIAL_DEPOSIT + INITIAL_LONG - longPosValue - initPosValue;

        // calculate the theoretical price of the USDN token from this balance
        uint256 theoreticalPrice =
            vaultBalance * uint256(currentPrice) * usdn.decimals() / (usdnInitialTotalSupply * wstETH.decimals());

        emit log_named_decimal_uint("vault balance (from liq price)", vaultBalance, 18);
        emit log_named_decimal_int("vault balance (from protocol) ", protocol.vaultAssetAvailable(currentPrice), 18);
        assertEq(
            protocol.usdnPrice(currentPrice, uint128(block.timestamp)), theoreticalPrice, "usdn price if long profit"
        );
    }
}

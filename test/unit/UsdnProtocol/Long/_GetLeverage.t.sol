// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { UsdnProtocolBaseFixture } from "../utils/Fixtures.sol";

/**
 * @custom:feature The _getLeverage internal function of the UsdnProtocolLong contract.
 * @custom:background Given a protocol initialized with 10 wstETH in the vault and 5 wstETH in a long position with a
 * leverage of ~2x
 */
contract TestUsdnProtocolLongGetLeverage is UsdnProtocolBaseFixture {
    function setUp() public {
        super._setUp(DEFAULT_PARAMS);
    }

    /**
     * @custom:scenario Call `_getLeverage` reverts when the liquidation price is equal or greater than
     * the start price.
     * @custom:given A liquidationPrice price greater than or equal to the StartPrice
     * @custom:when _getLeverage is called
     * @custom:then The transaction reverts with the `UsdnProtocolInvalidLiquidationPrice` error
     */
    function test_RevertWhen_getLeverageWithLiquidationPriceGreaterThanStartPrice() public {
        uint128 startPrice = 1000;
        uint128 liquidationPrice = 1000;

        /* ------------------------- startPrice == liquidationPrice ------------------------- */
        vm.expectRevert(
            abi.encodeWithSelector(UsdnProtocolInvalidLiquidationPrice.selector, liquidationPrice, startPrice)
        );
        protocol.i_getLeverage(startPrice, liquidationPrice);

        /* -------------------------- liquidationPrice > startPrice ------------------------- */
        liquidationPrice += 1;
        vm.expectRevert(
            abi.encodeWithSelector(UsdnProtocolInvalidLiquidationPrice.selector, liquidationPrice, startPrice)
        );
        protocol.i_getLeverage(startPrice, liquidationPrice);
    }

    /**
     * @custom:scenario Check calculations of `_getLeverage`
     * @custom:given A startPrice and a liquidationPrice
     * @custom:when The function "_getLeverage" is called with some parameters
     * @custom:then The leverage is calculated correctly
     */
    function test_getLeverageWithExpectedValue() public view {
        uint8 leverageDecimals = protocol.LEVERAGE_DECIMALS();
        uint256 leverage = protocol.i_getLeverage(1000, 1000 - 1);
        assertEq(leverage, 1000 * 10 ** leverageDecimals, "leverage should be 1000e21");

        leverage = protocol.i_getLeverage(10_389 ether, 10_158 ether);
        assertEq(leverage, 44_974_025_974_025_974_025_974, "leverage should be 44_974...");

        leverage = protocol.i_getLeverage(2000 ether, 1000 ether);
        assertEq(leverage, 2 * 10 ** leverageDecimals, "leverage should be 2e21");

        // worst case scenario
        leverage = protocol.i_getLeverage(type(uint128).max, type(uint128).max - 1);
        assertEq(
            leverage,
            340_282_366_920_938_463_463_374_607_431_768_211_455_000_000_000_000_000_000_000,
            "leverage should be 340_282..."
        );
    }
}

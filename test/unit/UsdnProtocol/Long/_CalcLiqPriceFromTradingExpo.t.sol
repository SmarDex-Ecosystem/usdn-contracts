// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { UsdnProtocolBaseFixture } from "test/unit/UsdnProtocol/utils/Fixtures.sol";

/// @custom:feature Test the _calcLiqPriceFromTradingExpo internal function of the long layer
contract TestUsdnProtocolLongCalcLiqPriceFromTradingExpo is UsdnProtocolBaseFixture {
    function setUp() public {
        super._setUp(DEFAULT_PARAMS);
    }

    /**
     * @custom:scenario The call revert when the total expo is 0
     * @custom:given The sum of the trading expo and the amount is 0
     * @custom:when _calcLiqPriceFromTradingExpo is called
     * @custom:then The call reverts with a UsdnProtocolZeroTotalExpo error
     */
    function test_RevertWhen_totalExpoIsZero() external {
        vm.expectRevert(UsdnProtocolZeroTotalExpo.selector);
        protocol.i_calcLiqPriceFromTradingExpo(2000 ether, 0, 0);
    }

    /**
     * @custom:scenario Calculate the liquidation price from the trading expo
     * @custom:given A leverage of 4x
     * @custom:or A leverage of 10x
     * @custom:when _calcLiqPriceFromTradingExpo is called
     * @custom:then The returned liquidation price is correct
     */
    function test_calcLiqPriceFromTradingExpo() public {
        uint128 amount = 2 ether;
        uint128 price = 2000 ether;

        // leverage 4x
        uint256 tradingExpo = uint256(amount) * 3;
        uint128 result = protocol.i_calcLiqPriceFromTradingExpo(price, amount, tradingExpo);
        assertEq(result, 1500 ether, "The result should be 0 (lowest possible index)");

        // leverage 10x
        tradingExpo = uint256(amount) * 9;
        result = protocol.i_calcLiqPriceFromTradingExpo(price, amount, tradingExpo);
        assertEq(result, 1800 ether, "The result should be 0 (lowest possible index)");
    }

    /**
     * @custom:scenario Check the calculations of _calcLiqPriceFromTradingExpo with
     * different amounts, prices and leverages
     * @custom:given an amount between 1 wei and uint128.max
     * @custom:and a price between 1 wei and uint128.max
     * @custom:and a leverage between the min and max leverage
     * @custom:when The trading expo is calculated
     * @custom:and _calcLiqPriceFromTradingExpo is called
     * @custom:then The expected liquidation price is returned
     * @param amount The amount of asset
     * @param price the current price of the asset
     * @param leverage the leverage to use
     */
    function testFuzz_calcLiqPriceFromTradingExpo(uint256 amount, uint256 price, uint256 leverage) public {
        amount = bound(amount, 1, type(uint128).max);
        price = bound(price, 1, type(uint128).max);
        leverage = bound(leverage, protocol.getMinLeverage(), protocol.getMaxLeverage());

        uint256 tradingExpo = (amount * leverage - amount) / protocol.LEVERAGE_DECIMALS();

        // non-optimized implementation
        // subtract one to the compensate loss in precision
        uint256 expectedLiquidationPrice = price - (amount * price / (tradingExpo + amount)) - 1;

        uint128 liquidationPrice = protocol.i_calcLiqPriceFromTradingExpo(uint128(price), uint128(amount), tradingExpo);

        assertEq(expectedLiquidationPrice, liquidationPrice, "The returned liquidation price is wrong");
    }
}

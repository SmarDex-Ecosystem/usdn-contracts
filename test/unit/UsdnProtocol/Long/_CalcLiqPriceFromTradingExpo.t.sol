// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { UsdnProtocolBaseFixture } from "../utils/Fixtures.sol";

import { UsdnProtocolConstantsLibrary as Constants } from
    "../../../../src/UsdnProtocol/libraries/UsdnProtocolConstantsLibrary.sol";

/// @custom:feature Test the {_calcLiqPriceFromTradingExpo} internal function of the long layer
contract TestUsdnProtocolLongCalcLiqPriceFromTradingExpo is UsdnProtocolBaseFixture {
    function setUp() public {
        super._setUp(DEFAULT_PARAMS);
    }

    /**
     * @custom:scenario The call reverts when the total expo is 0
     * @custom:given The sum of the trading expo and the amount is 0
     * @custom:when {_calcLiqPriceFromTradingExpo} is called
     * @custom:then The call reverts with a {UsdnProtocolZeroTotalExpo} error
     */
    function test_RevertWhen_totalExpoIsZero() public {
        vm.expectRevert(UsdnProtocolZeroTotalExpo.selector);
        protocol.i_calcLiqPriceFromTradingExpo(2000 ether, 0, 0);
    }

    /**
     * @custom:scenario Calculate the liquidation price from the trading expo
     * @custom:given A leverage of 4x
     * @custom:or A leverage of 10x
     * @custom:when {_calcLiqPriceFromTradingExpo} is called
     * @custom:then The returned liquidation price is correct
     */
    function test_calcLiqPriceFromTradingExpo() public view {
        uint128 amount = 2 ether;
        uint128 price = 2000 ether;

        // leverage 4x
        uint256 tradingExpo = uint256(amount) * 3;
        uint128 result = protocol.i_calcLiqPriceFromTradingExpo(price, amount, tradingExpo);
        assertEq(result, 1500 ether, "The result should equal the price - price / 4");

        // leverage 10x
        tradingExpo = uint256(amount) * 9;
        result = protocol.i_calcLiqPriceFromTradingExpo(price, amount, tradingExpo);
        assertEq(result, 1800 ether, "The result should equal the price - price / 10");
    }

    /**
     * @custom:scenario Check the calculations of {_calcLiqPriceFromTradingExpo} with
     * different amounts, prices and leverages
     * @custom:given An amount between 1 wei and uint128.max
     * @custom:and A price between 1 wei and uint128.max
     * @custom:and A leverage between the min and max leverage
     * @custom:when The trading expo is calculated
     * @custom:and {_calcLiqPriceFromTradingExpo} is called
     * @custom:then The expected liquidation price is returned
     * @param amount The amount of asset
     * @param price The current price of the asset
     * @param leverage The leverage to use
     */
    function testFuzz_calcLiqPriceFromTradingExpo(uint256 amount, uint256 price, uint256 leverage) public view {
        amount = bound(amount, 1, type(uint128).max);
        price = bound(price, 1, type(uint128).max);
        leverage = bound(leverage, protocol.getMinLeverage(), protocol.getMaxLeverage());

        uint256 tradingExpo = (amount * leverage - amount) / Constants.LEVERAGE_DECIMALS;

        // non-optimized implementation
        // subtract one to compensate for the loss in precision
        uint256 expectedLiquidationPrice = price - (amount * price / (tradingExpo + amount)) - 1;

        uint128 liquidationPrice = protocol.i_calcLiqPriceFromTradingExpo(uint128(price), uint128(amount), tradingExpo);

        assertEq(expectedLiquidationPrice, liquidationPrice, "The returned liquidation price is wrong");
    }
}

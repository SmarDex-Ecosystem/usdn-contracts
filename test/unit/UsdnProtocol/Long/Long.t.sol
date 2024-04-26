// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { UsdnProtocolBaseFixture } from "test/unit/UsdnProtocol/utils/Fixtures.sol";
import { ADMIN } from "test/utils/Constants.sol";

import { Position } from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import { ProtocolAction, TickData } from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";

/**
 * @custom:feature The getter functions of the USDN Protocol
 * @custom:background Given a protocol initialized at equilibrium
 */
contract TestUsdnProtocolLong is UsdnProtocolBaseFixture {
    function setUp() public {
        super._setUp(DEFAULT_PARAMS);
    }

    /**
     * @custom:scenario Check calculations of `_positionValue`
     * @custom:given A position for 1 wstETH with a starting price of $1000
     * @custom:and a leverage of 2x (liquidation price $500)
     * @custom:or a leverage of 4x (liquidation price $750)
     * @custom:when The current price is $2000 and the leverage is 2x
     * @custom:then The position value is 1.5 wstETH
     * @custom:when the current price is $1000 and the leverage is 2x
     * @custom:then the position value is 1 wstETH
     * @custom:when the current price is $500 and the leverage is 2x
     * @custom:then the position value is 0 wstETH
     * @custom:when the current price is $200 and the leverage is 2x
     * @custom:then the position value is -3 wstETH
     * @custom:when the current price is $2000 and the leverage is 4x
     * @custom:then the position value is 2.5 wstETH
     */
    function test_positionValue() public {
        uint128 positionTotalExpo = 2 ether;
        int256 value = protocol.i_positionValue(2000 ether, 500 ether, positionTotalExpo);
        assertEq(value, 1.5 ether, "Position value should be 1.5 ether");

        value = protocol.i_positionValue(1000 ether, 500 ether, positionTotalExpo);
        assertEq(value, 1 ether, "Position value should be 1 ether");

        value = protocol.i_positionValue(500 ether, 500 ether, positionTotalExpo);
        assertEq(value, 0 ether, "Position value should be 0");

        value = protocol.i_positionValue(200 ether, 500 ether, positionTotalExpo);
        assertEq(value, -3 ether, "Position value should be negative");

        positionTotalExpo = 4 ether;
        value = protocol.i_positionValue(2000 ether, 750 ether, positionTotalExpo);
        assertEq(value, 2.5 ether, "Position with 4x leverage should have a 2.5 ether value");
    }

    /**
     * @custom:scenario Check calculations of the `tickValue` function
     * @custom:given A tick with total expo 10 wstETH and a liquidation price around $500
     * @custom:when The current price is equal to the liquidation price without penalty
     * @custom:or the current price is 2x the liquidation price without penalty
     * @custom:or the current price is 0.5x the liquidation price without penalty
     * @custom:or the current price is equal to the liquidation price with penalty
     * @custom:then The tick value is 0 if the price is equal to the liquidation price without penalty
     * @custom:or the tick value is 5 wstETH if the price is 2x the liquidation price without penalty
     * @custom:or the tick value is -10 wstETH if the price is 0.5x the liquidation price without penalty
     * @custom:or the tick value is 0.198003465594229687 wstETH if the price is equal to the liquidation price with
     * penalty
     */
    function test_tickValue() public {
        int24 tick = protocol.getEffectiveTickForPrice(500 ether);
        uint128 liqPriceWithoutPenalty = protocol.getEffectivePriceForTick(
            tick - int24(uint24(protocol.getLiquidationPenalty())) * protocol.getTickSpacing()
        );
        TickData memory tickData =
            TickData({ totalExpo: 10 ether, totalPos: 1, liquidationPenalty: protocol.getLiquidationPenalty() });

        int256 value = protocol.i_tickValue(liqPriceWithoutPenalty, tick, tickData);
        assertEq(value, 0, "current price = liq price");

        value = protocol.i_tickValue(liqPriceWithoutPenalty * 2, tick, tickData);
        assertEq(value, 5 ether, "current price = 2x liq price");

        value = protocol.i_tickValue(liqPriceWithoutPenalty / 2, tick, tickData);
        assertEq(value, -10 ether, "current price = 0.5x liq price");

        value = protocol.i_tickValue(protocol.getEffectivePriceForTick(tick), tick, tickData);
        assertEq(value, 0.198003465594229687 ether, "current price = liq price with penalty");
    }

    /**
     * @custom:scenario Check that the leverage and total expo of a position is re-calculated on validation
     * @custom:given An initialized position
     * @custom:when The position is validated
     * @custom:and The price fluctuated a bit
     * @custom:and Funding calculations were applied
     * @custom:then The leverage of the position should be adjusted, changing the value of the total expo for the tick
     * and the protocol
     */
    function test_validateAPositionAfterPriceChangedRecalculateLeverageAndTotalExpo() external {
        uint128 price = 2000 ether;
        uint128 desiredLiqPrice = 1700 ether;

        uint256 initialTotalExpo = protocol.getTotalExpo();
        TickData memory tickData = protocol.getTickData(protocol.getEffectiveTickForPrice(desiredLiqPrice));

        assertEq(tickData.totalExpo, 0, "Total expo for future tick of position should be empty");

        // Initiate a long position
        (int24 tick, uint256 tickVersion, uint256 index) = setUpUserPositionInLong(
            OpenParams({
                user: address(this),
                untilAction: ProtocolAction.InitiateOpenPosition,
                positionSize: 1 ether,
                desiredLiqPrice: desiredLiqPrice,
                price: 2000 ether
            })
        );

        tickData = protocol.getTickData(tick);
        (Position memory position,) = protocol.getLongPosition(tick, tickVersion, index);

        // Calculate the total expo of the position after the initialization
        assertEq(
            initialTotalExpo + position.totalExpo,
            protocol.getTotalExpo(),
            "Total expo should have increased by the total expo of position"
        );
        assertEq(tickData.totalExpo, position.totalExpo, "Total expo on tick is not the expected value");

        _waitDelay();

        // Change the price
        price = 1999 ether;
        // Validate the position with the new price
        protocol.validateOpenPosition(abi.encode(price), EMPTY_PREVIOUS_DATA);

        uint256 previousExpo = position.totalExpo;
        // Get the updated position
        (position,) = protocol.getLongPosition(tick, tickVersion, index);
        uint256 newExpo = position.totalExpo;

        // Sanity check
        assertTrue(previousExpo != newExpo, "The expo changing is necessary for this test to work");

        // Calculate the total expo of the position after the validation
        assertEq(
            initialTotalExpo + position.totalExpo,
            protocol.getTotalExpo(),
            "Total expo should have increased by the position's new total expo"
        );

        tickData = protocol.getTickData(tick);
        assertEq(tickData.totalExpo, position.totalExpo, "Total expo on tick is not the expected value");
    }

    /**
     * @custom:scenario Call `initiateOpenPosition` reverts when the position size is lower than the minimum
     * @custom:given The amount of assets lower than the minimum long position
     * @custom:when initiateOpenPosition is called
     * @custom:then The transaction reverts with a UsdnProtocolLongPositionTooSmall error
     */
    function test_RevertWhen_initiateOpenPositionAmountTooLow() public {
        uint256 minLongPositionSize = 10 ** protocol.getAssetDecimals();
        vm.prank(ADMIN);
        protocol.setMinLongPosition(minLongPositionSize);

        vm.expectRevert(abi.encodeWithSelector(UsdnProtocolLongPositionTooSmall.selector));
        protocol.initiateOpenPosition(
            uint128(minLongPositionSize) - 1, 1000 ether, abi.encode(2000 ether), EMPTY_PREVIOUS_DATA, address(this)
        );
    }

    /**
     * @custom:scenario Check that the position is correctly initiated when its amount of collateral
     * is greater than the minimum long position
     * @custom:given A position size greater than the minimum long position
     * @custom:when initiateOpenPosition is called
     * @custom:then The transaction was accepted with a expected position
     */
    function test_initiateOpenPositionWithEnoughAssets() public {
        vm.prank(ADMIN);
        protocol.setMinLongPosition(1 ether);

        uint128 desiredLiqPrice = 1000 ether;

        uint256 initialTotalExpo = protocol.getTotalExpo();
        TickData memory tickData = protocol.getTickData(protocol.getEffectiveTickForPrice(desiredLiqPrice));

        assertEq(tickData.totalExpo, 0, "Total expo for future tick of position should be empty");

        // Initiate a long position
        (int24 tick, uint256 tickVersion, uint256 index) = setUpUserPositionInLong(
            OpenParams({
                user: address(this),
                untilAction: ProtocolAction.InitiateOpenPosition,
                positionSize: 1 ether,
                desiredLiqPrice: desiredLiqPrice,
                price: 2000 ether
            })
        );

        tickData = protocol.getTickData(tick);
        (Position memory position,) = protocol.getLongPosition(tick, tickVersion, index);

        // Calculate the total expo of the position after the initialization
        assertEq(
            initialTotalExpo + position.totalExpo,
            protocol.getTotalExpo(),
            "Total expo should have increased by the total expo of position"
        );
        assertEq(tickData.totalExpo, position.totalExpo, "Total expo on tick is not the expected value");
    }
}

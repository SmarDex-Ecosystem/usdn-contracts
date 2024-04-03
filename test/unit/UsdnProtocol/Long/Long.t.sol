// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { FixedPointMathLib } from "solady/src/utils/FixedPointMathLib.sol";

import { UsdnProtocolBaseFixture } from "test/unit/UsdnProtocol/utils/Fixtures.sol";

import { Position } from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import { TickMath } from "src/libraries/TickMath.sol";
import { ProtocolAction } from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";

/**
 * @custom:feature The getter functions of the USDN Protocol
 * @custom:background Given a protocol initialized at equilibrium
 */
contract TestUsdnProtocolLong is UsdnProtocolBaseFixture {
    function setUp() public {
        params = DEFAULT_PARAMS;
        params.initialDeposit = 4.919970269703463156 ether; // same as long trading expo
        super._setUp(params);
    }

    /**
     * @custom:scenario Check value of the `getMinLiquidationPrice` function
     * @custom:when The minimum leverage is 1.000000001
     * @custom:and The multiplier is 1x.
     */
    function test_getMinLiquidationPrice_multiplierEqOne() public {
        /**
         * 5000 - 5000 / 1.000000001 = 0.000004999999995001
         * tick(0.000004999999995001) = -122100 => + tickSpacing = -122000
         */
        assertEq(protocol.getMinLiquidationPrice(5000 ether), TickMath.getPriceAtTick(-122_000), "for price = 5000");

        /**
         * 10^12 - 10^12 / 1.000000001 < MINIMUM_PRICE
         * => minLiquidationPrice = getPriceAtTick(protocol.minTick() + protocol.getTickSpacing())
         */
        assertEq(
            protocol.getMinLiquidationPrice(10 ** 12),
            TickMath.getPriceAtTick(protocol.minTick() + protocol.getTickSpacing()),
            "for price = 1 * 10^12 wei"
        );
    }

    /**
     * @custom:scenario Check value of the `getMinLiquidationPrice` function
     * @custom:when The minimum leverage is 1.000000001
     * @custom:and The multiplier is > 1.
     */
    function test_getMinLiquidationPrice_multiplierGtOne() public {
        setUpUserPositionInLong(
            address(this), ProtocolAction.ValidateOpenPosition, 500 ether, params.initialPrice / 2, params.initialPrice
        );
        skip(1 days);
        setUpUserPositionInVault(address(this), ProtocolAction.ValidateDeposit, 1, params.initialPrice);

        assertGt(
            protocol.getLiquidationMultiplier(),
            10 ** protocol.LIQUIDATION_MULTIPLIER_DECIMALS(),
            "liquidation multiplier <= 1"
        );
        assertEq(protocol.getMinLiquidationPrice(5000 ether), 5_042_034_709_631, "wrong minimum liquidation price");
    }

    /**
     * @custom:scenario Check value of the `getMinLiquidationPrice` function
     * @custom:when The minimum leverage is 1.000000001
     * @custom:and The multiplier is < 1.
     */
    function test_getMinLiquidationPrice_multiplierLtOne() public {
        setUpUserPositionInVault(address(this), ProtocolAction.ValidateDeposit, 5000 ether, params.initialPrice);
        skip(6 days);
        setUpUserPositionInVault(address(this), ProtocolAction.ValidateDeposit, 1, params.initialPrice);

        assertLt(
            protocol.getLiquidationMultiplier(),
            10 ** protocol.LIQUIDATION_MULTIPLIER_DECIMALS(),
            "liquidation multiplier >= 1"
        );
        assertEq(protocol.getMinLiquidationPrice(5000 ether), 5_045_368_555_235, "wrong minimum liquidation price");
    }

    /**
     * @custom:scenario Check value of the `getMinLiquidationPrice` function
     * @custom:when The minimum leverage is 1
     * @custom:and The multiplier is 1x.
     */
    function test_getMinLiquidationPrice_minLeverageEqOne() public adminPrank {
        /**
         * 5000 - 5000 / 1 = 0
         * => minLiquidationPrice = getPriceAtTick(protocol.minTick() + protocol.getTickSpacing())
         */
        protocol.setMinLeverage(10 ** protocol.LEVERAGE_DECIMALS() + 1);
        assertEq(
            protocol.getMinLiquidationPrice(5000 ether),
            TickMath.getPriceAtTick(protocol.minTick() + protocol.getTickSpacing())
        );
    }

    /**
     * @custom:scenario Check value of the `getMinLiquidationPrice` function
     * @custom:when The minimum leverage is 1.1
     * @custom:and The multiplier is 1x.
     */
    function test_getMinLiquidationPrice_minLeverageEq1_1() public adminPrank {
        /**
         * 5000 - 5000 / 1.1 = 454.545454545454545455
         * tick(454.545454545454545455) = 61_100 => + tickSpacing = 61_200
         */
        protocol.setMinLeverage(11 * 10 ** (protocol.LEVERAGE_DECIMALS() - 1)); // = x1.1
        assertEq(protocol.getMinLiquidationPrice(5000 ether), TickMath.getPriceAtTick(61_200));
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
     * @custom:scenario Check calculations of `_calculatePositionTotalExpo`
     */
    function test_calculatePositionTotalExpo() public {
        uint256 expo = protocol.i_calculatePositionTotalExpo(1 ether, 2000 ether, 1500 ether);
        assertEq(expo, 4 ether, "Position total expo should be 4 ether");

        expo = protocol.i_calculatePositionTotalExpo(2 ether, 4000 ether, 1350 ether);
        assertEq(expo, 3_018_867_924_528_301_886, "Position total expo should be 3.018... ether");

        expo = protocol.i_calculatePositionTotalExpo(1 ether, 2000 ether, 1000 ether);
        assertEq(expo, 2 ether, "Position total expo should be 2 ether");
    }

    /**
     * @custom:scenario Call `_calculatePositionTotalExpo` reverts when the liquidation price is greater than
     * the start price.
     * @custom:given A liquidation price greater than or equal to the start price
     * @custom:when _calculatePositionTotalExpo is called
     * @custom:then The transaction reverts with a UsdnProtocolInvalidLiquidationPrice error
     */
    function test_RevertWhen_calculatePositionTotalExpoWithLiqPriceGreaterThanStartPrice() public {
        uint128 startPrice = 2000 ether;
        uint128 liqPrice = 2000 ether;

        /* ------------------------- startPrice == liqPrice ------------------------- */
        vm.expectRevert(abi.encodeWithSelector(UsdnProtocolInvalidLiquidationPrice.selector, liqPrice, startPrice));
        protocol.i_calculatePositionTotalExpo(1 ether, startPrice, liqPrice);

        /* -------------------------- liqPrice > startPrice ------------------------- */
        liqPrice = 2000 ether + 1;
        vm.expectRevert(abi.encodeWithSelector(UsdnProtocolInvalidLiquidationPrice.selector, liqPrice, startPrice));
        protocol.i_calculatePositionTotalExpo(1 ether, startPrice, liqPrice);
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
            tick - int24(protocol.getLiquidationPenalty()) * protocol.getTickSpacing()
        );

        int256 value = protocol.i_tickValue(liqPriceWithoutPenalty, tick, 10 ether);
        assertEq(value, 0, "current price = liq price");

        value = protocol.i_tickValue(liqPriceWithoutPenalty * 2, tick, 10 ether);
        assertEq(value, 5 ether, "current price = 2x liq price");

        value = protocol.i_tickValue(liqPriceWithoutPenalty / 2, tick, 10 ether);
        assertEq(value, -10 ether, "current price = 0.5x liq price");

        value = protocol.i_tickValue(protocol.getEffectivePriceForTick(tick), tick, 10 ether);
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
        uint256 totalExpoForTick =
            protocol.getCurrentTotalExpoByTick(protocol.getEffectiveTickForPrice(desiredLiqPrice));

        assertEq(totalExpoForTick, 0, "Total expo for future position's tick should be empty");

        // Initiate a long position
        (int24 tick, uint256 tickVersion, uint256 index) = setUpUserPositionInLong(
            address(this), ProtocolAction.InitiateOpenPosition, 1 ether, desiredLiqPrice, 2000 ether
        );

        totalExpoForTick = protocol.getCurrentTotalExpoByTick(tick);
        Position memory position = protocol.getLongPosition(tick, tickVersion, index);

        // Calculate the total expo of the position after the initialization
        assertEq(
            initialTotalExpo + position.totalExpo,
            protocol.getTotalExpo(),
            "Total expo should have increased by the position's total expo"
        );
        assertEq(totalExpoForTick, position.totalExpo, "Total expo on tick is not the expected value");

        _waitDelay();

        // Change the price
        price = 1999 ether;
        // Validate the position with the new price
        protocol.validateOpenPosition(abi.encode(price), EMPTY_PREVIOUS_DATA);

        uint256 previousExpo = position.totalExpo;
        // Get the updated position
        position = protocol.getLongPosition(tick, tickVersion, index);
        uint256 newExpo = position.totalExpo;

        // Sanity check
        assertTrue(previousExpo != newExpo, "The expo changing is necessary for this test to work");

        // Calculate the total expo of the position after the validation
        assertEq(
            initialTotalExpo + position.totalExpo,
            protocol.getTotalExpo(),
            "Total expo should have increased by the position's new total expo"
        );

        totalExpoForTick = protocol.getCurrentTotalExpoByTick(tick);
        assertEq(totalExpoForTick, position.totalExpo, "Total expo on tick is not the expected value");
    }
}

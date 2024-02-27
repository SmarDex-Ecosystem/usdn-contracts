// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { FixedPointMathLib } from "solady/src/utils/FixedPointMathLib.sol";

import { Position } from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import { UsdnProtocolBaseFixture } from "test/unit/UsdnProtocol/utils/Fixtures.sol";

import { TickMath } from "src/libraries/TickMath.sol";

/**
 * @custom:feature The getter functions of the USDN Protocol
 * @custom:background Given a protocol initialized with 10 wstETH in the vault and 5 wstETH in a long position with a
 * leverage of ~2x.
 */
contract TestUsdnProtocolLong is UsdnProtocolBaseFixture {
    function setUp() public {
        super._setUp(DEFAULT_PARAMS);
        wstETH.mintAndApprove(address(this), 100_000 ether, address(protocol), type(uint256).max);
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
         * => minLiquidationPrice = getPriceAtTick(protocol.getMinTick() + protocol.getTickSpacing())
         */
        assertEq(
            protocol.getMinLiquidationPrice(10 ** 12),
            TickMath.getPriceAtTick(protocol.getMinTick() + protocol.getTickSpacing()),
            "for price = 1 * 10^12 wei"
        );
    }

    /**
     * @custom:scenario Check value of the `getMinLiquidationPrice` function
     * @custom:when The minimum leverage is 1.000000001
     * @custom:and The multiplier is > 1.
     */
    function test_getMinLiquidationPrice_multiplierGtOne() public {
        bytes memory priceData = abi.encode(4000 ether);
        uint128 desiredLiqPrice =
            protocol.i_getLiquidationPrice(4000 ether, uint128(2 * 10 ** protocol.LEVERAGE_DECIMALS()));

        protocol.initiateOpenPosition(500 ether, desiredLiqPrice, priceData, "");
        protocol.validateOpenPosition(priceData, "");
        skip(1 days);
        protocol.initiateDeposit(1, priceData, "");
        protocol.validateDeposit(priceData, "");

        assertGt(
            protocol.getLiquidationMultiplier(),
            10 ** protocol.LIQUIDATION_MULTIPLIER_DECIMALS(),
            "liquidation multiplier <= 1"
        );
        assertEq(protocol.getMinLiquidationPrice(5000 ether), 5_002_844_036_506, "wrong minimum liquidation price");
    }

    /**
     * @custom:scenario Check value of the `getMinLiquidationPrice` function
     * @custom:when The minimum leverage is 1.000000001
     * @custom:and The multiplier is < 1.
     */
    function test_getMinLiquidationPrice_multiplierLtOne() public {
        bytes memory priceData = abi.encode(4000 ether);

        protocol.initiateDeposit(5000 ether, priceData, "");
        protocol.validateDeposit(priceData, "");
        skip(6 days);
        protocol.initiateDeposit(1, priceData, "");
        protocol.validateDeposit(priceData, "");

        assertLt(
            protocol.getLiquidationMultiplier(),
            10 ** protocol.LIQUIDATION_MULTIPLIER_DECIMALS(),
            "liquidation multiplier >= 1"
        );
        assertEq(protocol.getMinLiquidationPrice(5000 ether), 5_032_218_788_439, "wrong minimum liquidation price");
    }

    /**
     * @custom:scenario Check value of the `getMinLiquidationPrice` function
     * @custom:when The minimum leverage is 1
     * @custom:and The multiplier is 1x.
     */
    function test_getMinLiquidationPrice_minLeverageEqOne() public adminPrank {
        /**
         * 5000 - 5000 / 1 = 0
         * => minLiquidationPrice = getPriceAtTick(protocol.getMinTick() + protocol.getTickSpacing())
         */
        protocol.setMinLeverage(10 ** protocol.LEVERAGE_DECIMALS() + 1);
        assertEq(
            protocol.getMinLiquidationPrice(5000 ether),
            TickMath.getPriceAtTick(protocol.getMinTick() + protocol.getTickSpacing())
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
     * @custom:scenario Check calculations of `i_getPositionValue`
     * @custom:given A position for 1 wstETH with a starting price of $1000
     * @custom:and a leverage of 2x (liquidation price $500)
     * @custom:or a leverage of 4x (liquidation price $750)
     * @custom:when The current price is $2000 and the leverage is 2x
     * @custom:or the current price is $1000 and the leverage is 2x
     * @custom:or the current price is $500 and the leverage is 2x
     * @custom:or the current price is $2000 and the leverage is 4x
     * @custom:then The position value is 1.5 wstETH ($2000 at 2x)
     * @custom:or the position value is 1 wstETH ($1000 at 2x)
     * @custom:or the position value is 0 wstETH ($500 at 2x)
     * @custom:or the position value is 2.5 wstETH ($2000 at 4x)
     */
    function test_positionValue() public {
        // starting price is 1000 ether (liq at 500 with a leverage of 2x)
        uint256 value =
            protocol.i_getPositionValue(2000 ether, 500 ether, 1 ether, uint128(2 * 10 ** protocol.LEVERAGE_DECIMALS()));
        assertEq(value, 1.5 ether, "current price 2000");

        value =
            protocol.i_getPositionValue(1000 ether, 500 ether, 1 ether, uint128(2 * 10 ** protocol.LEVERAGE_DECIMALS()));
        assertEq(value, 1 ether, "current price 1000");

        value =
            protocol.i_getPositionValue(500 ether, 500 ether, 1 ether, uint128(2 * 10 ** protocol.LEVERAGE_DECIMALS()));
        assertEq(value, 0 ether, "current price 500");

        value =
            protocol.i_getPositionValue(2000 ether, 750 ether, 1 ether, uint128(4 * 10 ** protocol.LEVERAGE_DECIMALS()));
        assertEq(value, 2.5 ether, "current price 2000 leverage 4x");
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
        (int24 tick, uint256 tickVersion, uint256 index) =
            protocol.initiateOpenPosition(1 ether, desiredLiqPrice, abi.encode(price), "");

        totalExpoForTick = protocol.getCurrentTotalExpoByTick(tick);
        Position memory position = protocol.getLongPosition(tick, tickVersion, index);

        // Calculate the total expo of the position after the initialization
        uint256 expectedPositionTotalExpo =
            FixedPointMathLib.fullMulDiv(position.amount, position.leverage, 10 ** protocol.LEVERAGE_DECIMALS());
        assertEq(
            initialTotalExpo + expectedPositionTotalExpo,
            protocol.getTotalExpo(),
            "Total expo should have increased by the position's total expo"
        );
        assertEq(totalExpoForTick, expectedPositionTotalExpo, "Total expo on tick is not the expected value");

        skip(oracleMiddleware.getValidationDelay() + 1);

        // Change the price
        price = 1999 ether;
        // Validate the position with the new price
        protocol.validateOpenPosition(abi.encode(price), "");

        uint256 previousLeverage = position.leverage;
        // Get the updated position
        position = protocol.getLongPosition(tick, tickVersion, index);
        uint256 newLeverage = position.leverage;

        // Sanity check
        assertTrue(previousLeverage != newLeverage, "The leverage changing is necessary for this test to work");

        // Calculate the total expo of the position after the validation
        expectedPositionTotalExpo =
            FixedPointMathLib.fullMulDiv(position.amount, position.leverage, 10 ** protocol.LEVERAGE_DECIMALS());

        assertEq(
            initialTotalExpo + expectedPositionTotalExpo,
            protocol.getTotalExpo(),
            "Total expo should have increased by the position's new total expo"
        );

        totalExpoForTick = protocol.getCurrentTotalExpoByTick(tick);
        assertEq(totalExpoForTick, expectedPositionTotalExpo, "Total expo on tick is not the expected value");
    }

    /**
     * @custom:scenario Check that the user can close his opened position
     * @custom:given An initialized and validated position
     * @custom:when The user call initiateClosePosition
     * @custom:then The close position action is initialized
     */
    function test_canInitializeClosePosition() external {
        uint128 price = 2000 ether;
        uint128 desiredLiqPrice = 1700 ether;

        // Initiate a long position
        (int24 tick, uint256 tickVersion, uint256 index) =
            protocol.initiateOpenPosition(1 ether, desiredLiqPrice, abi.encode(price), "");
        skip(oracleMiddleware.getValidationDelay() + 1);
        // Validate the open position action
        protocol.validateOpenPosition(abi.encode(price), "");
        skip(oracleMiddleware.getValidationDelay() + 1);

        vm.expectEmit();
        emit InitiatedClosePosition(address(this), tick, tickVersion, index);
        protocol.initiateClosePosition(tick, tickVersion, index, abi.encode(price), "");
    }
}

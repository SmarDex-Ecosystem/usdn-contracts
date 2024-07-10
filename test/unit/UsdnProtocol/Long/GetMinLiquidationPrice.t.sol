// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import { UsdnProtocolBaseFixture } from "../utils/Fixtures.sol";

/**
 * @custom:feature The `getMinLiquidationPrice` function of the USDN Protocol
 * @custom:background Given a protocol initialized at equilibrium
 */
contract TestUsdnProtocolLongGetMinLiquidationPrice is UsdnProtocolBaseFixture {
    function setUp() public {
        params = DEFAULT_PARAMS;
        params.flags.enableFunding = true;
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
        assertEq(
            protocol.getMinLiquidationPrice(5000 ether), protocol.getEffectivePriceForTick(-122_000), "for price = 5000"
        );

        /**
         * 10^12 - 10^12 / 1.000000001 < MINIMUM_PRICE
         * => minLiquidationPrice = getPriceAtTick(protocol.minTick() + protocol.getTickSpacing())
         */
        assertEq(
            protocol.getMinLiquidationPrice(10 ** 12),
            protocol.getEffectivePriceForTick(protocol.minTick() + protocol.getTickSpacing()),
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
            OpenParams(
                address(this),
                ProtocolAction.ValidateOpenPosition,
                500 ether,
                params.initialPrice / 2,
                params.initialPrice
            )
        );
        skip(1 days);
        setUpUserPositionInVault(address(this), ProtocolAction.ValidateDeposit, 1, params.initialPrice);

        assertGt(
            protocol.i_calcFixedPrecisionMultiplier(
                params.initialPrice,
                protocol.getTotalExpo() - protocol.getBalanceLong(),
                protocol.getLiqMultiplierAccumulator()
            ),
            10 ** protocol.LIQUIDATION_MULTIPLIER_DECIMALS(),
            "liquidation multiplier <= 1"
        );
        assertEq(protocol.getMinLiquidationPrice(5000 ether), 5_042_540_928_255, "wrong minimum liquidation price");
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
            protocol.i_calcFixedPrecisionMultiplier(
                params.initialPrice,
                protocol.getTotalExpo() - protocol.getBalanceLong(),
                protocol.getLiqMultiplierAccumulator()
            ),
            10 ** protocol.LIQUIDATION_MULTIPLIER_DECIMALS(),
            "liquidation multiplier >= 1"
        );
        assertEq(protocol.getMinLiquidationPrice(5000 ether), 5_043_322_074_974, "wrong minimum liquidation price");
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
            protocol.getEffectivePriceForTick(protocol.minTick() + protocol.getTickSpacing())
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
        assertEq(protocol.getMinLiquidationPrice(5000 ether), protocol.getEffectivePriceForTick(61_200));
    }
}

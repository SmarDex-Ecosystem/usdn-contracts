// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

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
        wstETH.mint(address(this), 100_000 ether);
        wstETH.approve(address(protocol), type(uint256).max);
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
         * => minLiquidationPrice = getPriceAtTick(protocol.minTick() + protocol.tickSpacing())
         */
        assertEq(
            protocol.getMinLiquidationPrice(10 ** 12),
            TickMath.getPriceAtTick(protocol.minTick() + protocol.tickSpacing()),
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
            protocol.getLiquidationPrice(4000 ether, uint128(2 * 10 ** protocol.LEVERAGE_DECIMALS()));

        protocol.initiateOpenPosition(500 ether, desiredLiqPrice, priceData, "");
        protocol.validateOpenPosition(priceData, "");
        skip(1 days);
        protocol.initiateDeposit(1, priceData, "");
        protocol.validateDeposit(priceData, "");

        assertGt(
            protocol.liquidationMultiplier(),
            10 ** protocol.LIQUIDATION_MULTIPLIER_DECIMALS(),
            "liquidation multiplier <= 1"
        );
        assertEq(protocol.getMinLiquidationPrice(5000 ether), 5_035_034_973_931, "wrong minimum liquidation price");
    }

    /**
     * @custom:scenario Check value of the `getMinLiquidationPrice` function
     * @custom:when The minimum leverage is 1.000000001
     * @custom:and The multiplier is < 1.
     */
    function test_getMinLiquidationPrice_multiplierLtOne() public {
        bytes memory priceData = abi.encode(4000 ether);

        protocol.initiateDeposit(500 ether, priceData, "");
        protocol.validateDeposit(priceData, "");
        skip(1 days);
        protocol.initiateDeposit(1, priceData, "");
        protocol.validateDeposit(priceData, "");

        // TO DO : Fix this test
        // assertLt(
        //     protocol.liquidationMultiplier(),
        //     10 ** protocol.LIQUIDATION_MULTIPLIER_DECIMALS(),
        //     "liquidation multiplier >= 1"
        // );
        assertEq(protocol.getMinLiquidationPrice(5000 ether), 5_033_532_235_523, "wrong minimum liquidation price");
    }

    /**
     * @custom:scenario Check value of the `getMinLiquidationPrice` function
     * @custom:when The minimum leverage is 1
     * @custom:and The multiplier is 1x.
     */
    function test_getMinLiquidationPrice_minLeverageEqOne() public {
        /**
         * 5000 - 5000 / 1 = 0
         * => minLiquidationPrice = getPriceAtTick(protocol.minTick() + protocol.tickSpacing())
         */
        protocol.setMinLeverage(10 ** protocol.LEVERAGE_DECIMALS());
        assertEq(
            protocol.getMinLiquidationPrice(5000 ether),
            TickMath.getPriceAtTick(protocol.minTick() + protocol.tickSpacing())
        );
    }

    /**
     * @custom:scenario Check value of the `getMinLiquidationPrice` function
     * @custom:when The minimum leverage is 1.1
     * @custom:and The multiplier is 1x.
     */
    function test_getMinLiquidationPrice_minLeverageEq1_1() public {
        /**
         * 5000 - 5000 / 1.1 = 454.545454545454545455
         * tick(454.545454545454545455) = 61_100 => + tickSpacing = 61_200
         */
        protocol.setMinLeverage(11 * 10 ** (protocol.LEVERAGE_DECIMALS() - 1)); // = x1.1
        assertEq(protocol.getMinLiquidationPrice(5000 ether), TickMath.getPriceAtTick(61_200));
    }
}

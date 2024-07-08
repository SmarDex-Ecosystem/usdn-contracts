// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import { UsdnProtocolBaseFixture } from "../utils/Fixtures.sol";

import { HugeUint } from "../../../../src/libraries/HugeUint.sol";
import { TickMath } from "../../../../src/libraries/TickMath.sol";

/**
 * @custom:feature The `getMinLiquidationPrice` function of the USDN Protocol
 * @custom:background Given a protocol initialized at equilibrium
 * @custom:and A current price of 5000 USD per asset
 */
contract TestUsdnProtocolLongGetMinLiquidationPrice is UsdnProtocolBaseFixture {
    Position firstPos;
    uint256 tradingExpo;
    HugeUint.Uint512 liqMulAcc;
    uint128 price = 5000 ether;

    function setUp() public {
        params = DEFAULT_PARAMS;
        params.flags.enableFunding = true;
        super._setUp(params);
        (firstPos,) = protocol.getLongPosition(initialPosition);
        tradingExpo = uint256(
            int256(protocol.getTotalExpo()) - protocol.longAssetAvailableWithFunding(price, uint128(block.timestamp))
        );
        liqMulAcc = protocol.getLiqMultiplierAccumulator();
    }

    /**
     * @custom:scenario Check value of the `getMinLiquidationPrice` function
     * @custom:given The price of the asset is 5000 USD
     * @custom:when The minimum leverage is 1.000000001
     * @custom:and The multiplier is 1x
     * @custom:then The min liquidation price is the expected price
     */
    function test_getMinLiquidationPrice_multiplierEqOne() public {
        // 5000 - 5000 / 1.000000001 = 0.000004999999995001
        assertEq(
            protocol.getMinLiquidationPrice(price),
            protocol.getEffectivePriceForTick(
                protocol.getEffectiveTickForPrice(4_999_999_995_001, price, tradingExpo, liqMulAcc, _tickSpacing)
                    + _tickSpacing,
                price,
                tradingExpo,
                liqMulAcc
            ),
            "for price = 5000"
        );
    }

    /**
     * @custom:scenario Check value of the `getMinLiquidationPrice` function
     * @custom:when The minimum leverage is 1.000000001
     * @custom:and The multiplier is > 1.
     * @custom:then The min liquidation price is the expected price
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

        tradingExpo = uint256(
            int256(protocol.getTotalExpo()) - protocol.longAssetAvailableWithFunding(price, uint128(block.timestamp))
        );
        liqMulAcc = protocol.getLiqMultiplierAccumulator();
        assertGt(
            protocol.i_calcFixedPrecisionMultiplier(
                params.initialPrice,
                protocol.getTotalExpo() - protocol.getBalanceLong(),
                protocol.getLiqMultiplierAccumulator()
            ),
            10 ** protocol.LIQUIDATION_MULTIPLIER_DECIMALS(),
            "liquidation multiplier <= 1"
        );
        // 5000 - 5000 / 1.000000001 = 0.000004999999995001
        assertEq(
            protocol.getMinLiquidationPrice(price),
            protocol.getEffectivePriceForTick(
                protocol.getEffectiveTickForPrice(4_999_999_995_001, price, tradingExpo, liqMulAcc, _tickSpacing)
                    + _tickSpacing,
                price,
                tradingExpo,
                liqMulAcc
            ),
            "wrong minimum liquidation price"
        );
    }

    /**
     * @custom:scenario Check value of the `getMinLiquidationPrice` function
     * @custom:when The minimum leverage is 1.000000001
     * @custom:and The multiplier is < 1
     * @custom:then The min liquidation price is the expected price
     */
    function test_getMinLiquidationPrice_multiplierLtOne() public {
        setUpUserPositionInVault(address(this), ProtocolAction.ValidateDeposit, price, params.initialPrice);
        skip(6 days);
        setUpUserPositionInVault(address(this), ProtocolAction.ValidateDeposit, 1, params.initialPrice);

        tradingExpo = uint256(
            int256(protocol.getTotalExpo()) - protocol.longAssetAvailableWithFunding(price, uint128(block.timestamp))
        );
        liqMulAcc = protocol.getLiqMultiplierAccumulator();
        assertLt(
            protocol.i_calcFixedPrecisionMultiplier(params.initialPrice, tradingExpo, liqMulAcc),
            10 ** protocol.LIQUIDATION_MULTIPLIER_DECIMALS(),
            "liquidation multiplier >= 1"
        );
        // 5000 - 5000 / 1.000000001 = 0.000004999999995001
        assertEq(
            protocol.getMinLiquidationPrice(price),
            protocol.getEffectivePriceForTick(
                protocol.getEffectiveTickForPrice(4_999_999_995_001, price, tradingExpo, liqMulAcc, _tickSpacing)
                    + _tickSpacing,
                price,
                tradingExpo,
                liqMulAcc
            ),
            "wrong minimum liquidation price"
        );
    }

    /**
     * @custom:scenario Check value of the `getMinLiquidationPrice` function
     * @custom:when The minimum leverage is 1
     * @custom:and The multiplier is 1x
     * @custom:then The min liquidation price is the price of the lowest usable tick + tick spacing
     */
    function test_getMinLiquidationPrice_minLeverageEqOne() public adminPrank {
        uint256 newMinLeverage = 10 ** protocol.LEVERAGE_DECIMALS() + 1;
        // sanity check
        assertLt(
            5000 ether - 5000 ether * 10 ** protocol.LEVERAGE_DECIMALS() / newMinLeverage,
            TickMath.MIN_PRICE,
            "Expected liquidation price should be below MIN_PRICE"
        );
        /**
         * 5000 - 5000 / 1.00...01 < MIN_PRICE
         * => minLiquidationPrice = getPriceAtTick(protocol.minTick() + protocol.getTickSpacing())
         */
        protocol.setMinLeverage(newMinLeverage);
        assertEq(
            protocol.getMinLiquidationPrice(price),
            TickMath.getPriceAtTick(protocol.minTick() + protocol.getTickSpacing()),
            "liquidation price should be equal to the min tick price + tick spacing"
        );
    }

    /**
     * @custom:scenario Check value of the `getMinLiquidationPrice` function
     * @custom:when The minimum leverage is 1.1
     * @custom:and The multiplier is 1x
     * @custom:then The min liquidation price is the expected price
     */
    function test_getMinLiquidationPrice_minLeverageEq1_1() public adminPrank {
        protocol.setMinLeverage(11 * 10 ** (protocol.LEVERAGE_DECIMALS() - 1)); // = x1.1
        // 5000 - 5000 / 1.1 = 454.545454545454545455
        assertEq(
            protocol.getMinLiquidationPrice(price),
            protocol.getEffectivePriceForTick(
                protocol.getEffectiveTickForPrice(
                    454_545_454_545_454_545_455, price, tradingExpo, liqMulAcc, _tickSpacing
                ) + _tickSpacing,
                price,
                tradingExpo,
                liqMulAcc
            )
        );
    }
}

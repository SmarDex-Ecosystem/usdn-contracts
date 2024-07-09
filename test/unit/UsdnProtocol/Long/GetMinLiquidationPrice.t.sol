// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import { ADMIN } from "../../../utils/Constants.sol";
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
            protocol.getMinLiquidationPrice(price, uint128(block.timestamp)),
            protocol.getEffectivePriceForTick(
                protocol.getEffectiveTickForPrice(4_999_999_995_001, price, tradingExpo, liqMulAcc, _tickSpacing)
                    + (_tickSpacing * int24(uint24(protocol.getLiquidationPenalty() + 2))),
                price,
                tradingExpo,
                liqMulAcc
            ),
            "for price = 5000"
        );

        skip(1 hours);
        tradingExpo = uint256(
            int256(protocol.getTotalExpo()) - protocol.longAssetAvailableWithFunding(price, uint128(block.timestamp))
        );
        assertEq(
            protocol.getMinLiquidationPrice(price, uint128(block.timestamp)),
            protocol.getEffectivePriceForTick(
                protocol.getEffectiveTickForPrice(4_999_999_995_001, price, tradingExpo, liqMulAcc, _tickSpacing)
                    + (_tickSpacing * int24(uint24(protocol.getLiquidationPenalty() + 2))),
                price,
                tradingExpo,
                liqMulAcc
            ),
            "for price = 5000 an hour later"
        );
    }

    /**
     * @custom:scenario Check value of the `getMinLiquidationPrice` function
     * @custom:when The minimum leverage is 1.000000001
     * @custom:and The multiplier is > 1
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
            protocol.getMinLiquidationPrice(price, uint128(block.timestamp)),
            protocol.getEffectivePriceForTick(
                protocol.getEffectiveTickForPrice(4_999_999_995_001, price, tradingExpo, liqMulAcc, _tickSpacing)
                    + (_tickSpacing * int24(uint24(protocol.getLiquidationPenalty() + 2))),
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
        setUpUserPositionInVault(address(this), ProtocolAction.ValidateDeposit, 500 ether, params.initialPrice);
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
            protocol.getMinLiquidationPrice(price, uint128(block.timestamp)),
            protocol.getEffectivePriceForTick(
                protocol.getEffectiveTickForPrice(4_999_999_995_001, price, tradingExpo, liqMulAcc, _tickSpacing)
                    + (_tickSpacing * int24(uint24(protocol.getLiquidationPenalty() + 2))),
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
            protocol.getMinLiquidationPrice(price, uint128(block.timestamp)),
            TickMath.getPriceAtTick(
                protocol.minTick() + (_tickSpacing * int24(uint24(protocol.getLiquidationPenalty() + 2)))
            ),
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
            protocol.getMinLiquidationPrice(price, uint128(block.timestamp)),
            protocol.getEffectivePriceForTick(
                protocol.getEffectiveTickForPrice(
                    454_545_454_545_454_545_455, price, tradingExpo, liqMulAcc, _tickSpacing
                ) + (_tickSpacing * int24(uint24(protocol.getLiquidationPenalty() + 2))),
                price,
                tradingExpo,
                liqMulAcc
            )
        );
    }

    /**
     * @custom:scenario The price returned by {getMinLiquidationPrice} can be used to open a position
     * @custom:given Fundings are enabled
     * @custom:when getMinLiquidationPrice is called
     * @custom:then The price returned can always be used to open a position
     * @param startPrice The price at which the position will be opened
     * @param minLeverage The min leverage of the protocol
     * @param elapsedSeconds The amount of time to wait before calling the function
     * @param imbalanceBps The imbalance before the amount of time to wait
     */
    function testFuzz_getMinLiquidationPriceCanBeUsedToOpenAPosition(
        uint256 startPrice,
        uint256 minLeverage,
        uint256 elapsedSeconds,
        int256 imbalanceBps
    ) public {
        uint256 levDecimals = protocol.LEVERAGE_DECIMALS();
        imbalanceBps = bound(imbalanceBps, -10_000, 10_000); // bound between -100%/+100%
        minLeverage = bound(minLeverage, 10 ** levDecimals + 1, (10 * 10 ** levDecimals));
        startPrice = bound(startPrice, 1000 ether, 1_000_000 ether);
        elapsedSeconds = bound(elapsedSeconds, 30 minutes, 1 weeks);

        uint128 amount;
        if (imbalanceBps < 0) {
            amount = params.initialDeposit * uint128(uint256(imbalanceBps * -1)) / 10_000;
            setUpUserPositionInVault(address(this), ProtocolAction.ValidateDeposit, amount, params.initialPrice);
        } else if (imbalanceBps > 0) {
            amount = params.initialLong * uint128(uint256(imbalanceBps)) / 10_000;
            setUpUserPositionInLong(
                OpenParams(
                    address(this),
                    ProtocolAction.ValidateOpenPosition,
                    amount,
                    params.initialPrice / 2,
                    params.initialPrice
                )
            );
        }

        vm.startPrank(ADMIN);
        protocol.setMaxLeverage(100 * 10 ** protocol.LEVERAGE_DECIMALS());
        protocol.setMinLeverage(minLeverage);
        vm.stopPrank();

        skip(elapsedSeconds);
        uint128 liqPrice = protocol.getMinLiquidationPrice(uint128(startPrice), uint128(block.timestamp - 30 minutes));

        wstETH.mintAndApprove(address(this), 1 ether, address(protocol), 1 ether);
        protocol.initiateOpenPosition(
            1 ether,
            liqPrice,
            address(this),
            payable(address(this)),
            NO_PERMIT2,
            abi.encode(startPrice),
            EMPTY_PREVIOUS_DATA
        );
    }
}

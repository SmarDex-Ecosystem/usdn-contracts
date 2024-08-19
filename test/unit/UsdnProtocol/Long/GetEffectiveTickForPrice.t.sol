// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { UsdnProtocolBaseFixture } from "../utils/Fixtures.sol";

import { HugeUint } from "../../../../src/libraries/HugeUint.sol";
import { TickMath } from "../../../../src/libraries/TickMath.sol";

/**
 * @custom:feature The getEffectiveTickForPrice public function of the UsdnProtocolLong contract.
 * @custom:background Given a protocol initialized with default parameters
 */
contract TestUsdnProtocolLongGetEffectiveTickForPrice is UsdnProtocolBaseFixture {
    using HugeUint for HugeUint.Uint512;

    function setUp() public {
        super._setUp(DEFAULT_PARAMS);
    }

    /**
     * @custom:scenario Fuzzing the `getEffectiveTickForPrice` function and return expected minTick
     * @custom:given A tickSpacing between 1 and 10_000
     * @custom:when getEffectiveTickForPrice is called (ignoring funding)
     * @custom:then The function should return expected minTick
     */
    function testFuzz_getEffectiveTickForPriceExpectedMinTick(int24 tickSpacing) public view {
        tickSpacing = int24(bound(tickSpacing, 1, 10_000));
        int24 expectedMinTick = TickMath.minUsableTick(tickSpacing);

        /* ------------------ unadjustedPrice < TickMath.MIN_PRICE ------------------ */
        uint128 price = 9999;
        assertLt(
            protocol.i_unadjustPrice(price, 0, 0, HugeUint.wrap(0)),
            TickMath.MIN_PRICE,
            "unadjustPrice should be lower than minPrice"
        );
        int24 tick = protocol.getEffectiveTickForPrice(price, 0, 0, HugeUint.wrap(0), tickSpacing);
        assertEq(tick, expectedMinTick, "tick should be equal to minTick");
    }

    /**
     * @custom:scenario Call `getEffectiveTickForPrice` and return expected tick
     * @custom:given A price, assetPrice, longTradingExpo and accumulator
     * @custom:when getEffectiveTickForPrice is called with price 60_000 ether
     * @custom:then The function should return tick_ = -303_500
     * @custom:when getEffectiveTickForPrice is called with price 10_000
     * @custom:then The function should return tick_ = minTick
     */
    function test_getEffectiveTickForPriceTickLowerThanZero() public view {
        /* ------------------------ minUsableTick < tick_ < 0 ----------------------- */
        int24 tickSpacing = 100;
        uint128 price = 60_000 ether;
        uint256 assetPrice = 150 ether;
        uint256 longTradingExpo = 300 ether;
        HugeUint.Uint512 memory accumulator = HugeUint.wrap(50_000 ether);

        assertGt(
            protocol.i_unadjustPrice(price, assetPrice, longTradingExpo, accumulator),
            TickMath.MIN_PRICE,
            "unadjustPrice should be greater than minPrice"
        );
        int24 tick = protocol.getEffectiveTickForPrice(price, assetPrice, longTradingExpo, accumulator, tickSpacing);
        assertEq(tick, -303_500, "tick should be equal to -303_500");

        /* -------------------------- tick_ < minUsableTick ------------------------- */
        int24 expectedMinTick = protocol.minTick();
        price = 10_000;

        assertEq(
            protocol.i_unadjustPrice(price, 0, 0, HugeUint.wrap(0)), price, "unadjustPrice should be equal to price"
        );
        tick = protocol.getEffectiveTickForPrice(price, 0, 0, HugeUint.wrap(0), tickSpacing);
        assertEq(tick, expectedMinTick, "tick should be equal to minTick");
    }

    /**
     * @custom:scenario Call `getEffectiveTickForPrice` and return expected tick_ >= 0
     * @custom:given A price, assetPrice, longTradingExpo and accumulator
     * @custom:when getEffectiveTickForPrice is called with price 1 ether
     * @custom:then The function should return tick_ = 0
     * @custom:when getEffectiveTickForPrice is called with price 5_000_000_000 ether
     * @custom:then The function should return tick_ > 0
     */
    function test_getEffectiveTickForPriceTickGreaterThanOrEqualZero() public view {
        /* -------------------------------- tick_ = 0 ------------------------------- */
        int24 tickSpacing = 100;
        uint128 price = 1 ether;
        int24 tick = protocol.getEffectiveTickForPrice(price, 0, 0, HugeUint.wrap(0), tickSpacing);
        assertEq(tick, 0, "tick should be equal to 0");

        /* -------------------------------- tick_ > 0 ------------------------------- */
        price = 5_000_000_000 ether;
        tick = protocol.getEffectiveTickForPrice(price, 0, 0, HugeUint.wrap(0), tickSpacing);
        assertEq(tick, 223_300, "tick should be equal to 223300");
    }
}

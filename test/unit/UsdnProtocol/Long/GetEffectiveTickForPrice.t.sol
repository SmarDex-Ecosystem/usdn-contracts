// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { FixedPointMathLib } from "solady/src/utils/FixedPointMathLib.sol";

import { UsdnProtocolBaseFixture } from "test/unit/UsdnProtocol/utils/Fixtures.sol";

/// @custom:feature Test the getEffectiveTickForPrice public function of the UsdnProtocolLong contract
contract TestUsdnProtocolLongGetEffectiveTickForPrice is UsdnProtocolBaseFixture {
    function setUp() public {
        super._setUp(DEFAULT_PARAMS);
    }

    /**
     * @custom:scenario Call `getEffectiveTickForPrice` and return expected minTick
     * @custom:given A price and liqMultiplier
     * @custom:when getEffectiveTickForPrice is called
     * @custom:then The function should return expected minTick
     */
    function test_getEffectiveTickForPriceExpectedMinTick() external {
        int24 expectedMinTick = protocol.minTick();

        /* ---------------- priceWithMultiplier = TickMath.MIN_PRICE ---------------- */
        uint256 liqMultiplier = 2000 * 10e38;
        // price = 10000 * liqMultiplier / 10e38 = 20000000
        uint128 price = 20_000_000;
        int24 minTick = protocol.getEffectiveTickForPrice(price, liqMultiplier);
        assertEq(minTick, expectedMinTick, "first tick should be equal to minTick");

        /* ---------------- priceWithMultiplier < TickMath.MIN_PRICE ---------------- */
        liqMultiplier = 2000 * 10e38;
        // price = 9999 * liqMultiplier / 10e38 = 199998000
        price = 199_998_000;
        minTick = protocol.getEffectiveTickForPrice(price, liqMultiplier);
        assertEq(minTick, expectedMinTick, "second tick should be equal to minTick");
    }

    /**
     * @custom:scenario Call `getEffectiveTickForPrice` and return expected minUsableTick < tick_ < 0
     * @custom:given A price and liqMultiplier
     * @custom:when getEffectiveTickForPrice is called
     * @custom:then The function should return expected tick_
     */
    function test_getEffectiveTickForPriceTickLowerThanZero() external {
        /* ------------------------ minUsableTick < tick_ < 0 ----------------------- */
        uint256 liqMultiplier = 2000 * 10e32;
        uint128 price = 1_999_980_000;
        int24 tick = protocol.getEffectiveTickForPrice(price, liqMultiplier);
        assertEq(tick, -161_200, "tick should be -161200");

        /* -------------------------- tick_ < minUsableTick ------------------------- */
        int24 expectedMinTick = protocol.minTick();
        liqMultiplier = 10 ** protocol.LIQUIDATION_MULTIPLIER_DECIMALS();
        price = uint128(protocol.i_minPrice()) + 1;
        tick = protocol.getEffectiveTickForPrice(price, liqMultiplier);
        assertEq(tick, expectedMinTick, "tick should be equal to minTick");
    }

    /**
     * @custom:scenario Call `getEffectiveTickForPrice` and return expected tick_ >= 0
     * @custom:given A price and liqMultiplier
     * @custom:when getEffectiveTickForPrice is called
     * @custom:then The function should return expected tick_
     */
    function test_getEffectiveTickForPriceTickGreaterThanOrEqualZero() external {
        /* -------------------------------- tick_ = 0 ------------------------------- */
        uint256 liqMultiplier = 1999 * 10e25;
        uint128 price = 1_999_980_000;
        int24 tick = protocol.getEffectiveTickForPrice(price, liqMultiplier);
        assertEq(tick, 0, "tick should be 0 with liqMultiplier 1999 * 10e25");

        liqMultiplier = 1981 * 10e25;
        price = 1_999_980_000;
        tick = protocol.getEffectiveTickForPrice(price, liqMultiplier);
        assertEq(tick, 0, "tick should be 0 with liqMultiplier 1981 * 10e25");

        /* -------------------------------- tick_ > 0 ------------------------------- */
        liqMultiplier = 2000 * 10e10;
        price = 2_000_000_000;
        tick = protocol.getEffectiveTickForPrice(price, liqMultiplier);
        assertEq(tick, 345_400, "tick should be 345400");
    }
}

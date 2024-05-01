// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { UsdnProtocolBaseFixture } from "test/unit/UsdnProtocol/utils/Fixtures.sol";

import { HugeUint } from "src/libraries/HugeUint.sol";
import { TickMath } from "src/libraries/TickMath.sol";

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
     * @custom:given A price, assetPrice, longTradingExpo and accumulator
     * @custom:when getEffectiveTickForPrice is called
     * @custom:then The function should return expected minTick
     */
    function testFuzz_getEffectiveTickForPriceExpectedMinTick(int24 tickSpacing) external {
        if (tickSpacing == 0) {
            return;
        }
        int24 expectedMinTick = TickMath.minUsableTick(tickSpacing);
        uint256 minPrice = protocol.i_minPrice();

        /* ------------------ unadjustedPrice < TickMath.MIN_PRICE ------------------ */
        uint128 price = 20 ether;
        uint256 assetPrice = 2000 ether;
        uint256 longTradingExpo = 300 ether;
        HugeUint.Uint512 memory accumulator = HugeUint.wrap(5000 ether);
        assertLt(
            protocol.i_unadjustPrice(price, assetPrice, longTradingExpo, accumulator),
            minPrice,
            "unadjustPrice should be lower than minPrice"
        );
        int24 tick = protocol.getEffectiveTickForPrice(price, assetPrice, longTradingExpo, accumulator, tickSpacing);
        assertEq(tick, expectedMinTick, "tick should be equal to minTick");
    }

    /**
     * @custom:scenario Call `getEffectiveTickForPrice` and return expected minUsableTick < tick_ < 0
     * @custom:given A price, assetPrice, longTradingExpo and accumulator
     * @custom:when getEffectiveTickForPrice is called
     * @custom:then The function should return expected tick
     */
    function test_getEffectiveTickForPriceTickLowerThanZero() external {
        /* ------------------------ minUsableTick < tick_ < 0 ----------------------- */
        uint256 minPrice = protocol.i_minPrice();
        int24 tickSpacing = 100;
        uint128 price = 60_000 ether;
        uint256 assetPrice = 150 ether;
        uint256 longTradingExpo = 300 ether;
        HugeUint.Uint512 memory accumulator = HugeUint.wrap(50_000 ether);

        assertGt(
            protocol.i_unadjustPrice(price, assetPrice, longTradingExpo, accumulator),
            minPrice,
            "unadjustPrice should be greater than minPrice"
        );
        int24 tick = protocol.getEffectiveTickForPrice(price, assetPrice, longTradingExpo, accumulator, tickSpacing);
        assertEq(tick, -303_500, "tick should be equal to -303_500");

        /* -------------------------- tick_ < minUsableTick ------------------------- */
        int24 expectedMinTick = protocol.minTick();
        tickSpacing = 100;
        price = 10_000;
        assetPrice = 100 ether;
        longTradingExpo = 100 ether;
        accumulator = HugeUint.wrap(0 ether);

        assertEq(
            protocol.i_unadjustPrice(price, assetPrice, longTradingExpo, accumulator),
            price,
            "unadjustPrice should be equal to price"
        );
        tick = protocol.getEffectiveTickForPrice(price, assetPrice, longTradingExpo, accumulator, tickSpacing);
        assertEq(tick, expectedMinTick, "tick should be equal to minTick");
    }

    /**
     * @custom:scenario Call `getEffectiveTickForPrice` and return expected tick_ >= 0
     * @custom:given A price, assetPrice, longTradingExpo and accumulator
     * @custom:when getEffectiveTickForPrice is called
     * @custom:then The function should return expected tick
     */
    function test_getEffectiveTickForPriceTickGreaterThanOrEqualZero() external {
        /* -------------------------------- tick_ = 0 ------------------------------- */
        int24 tickSpacing = 100;
        uint128 price = 2_950_000_000 ether;
        uint256 assetPrice = 130 ether;
        uint256 longTradingExpo = 9 ether;
        HugeUint.Uint512 memory accumulator = HugeUint.wrap(400_000_000_000 ether);
        int24 tick = protocol.getEffectiveTickForPrice(price, assetPrice, longTradingExpo, accumulator, tickSpacing);
        assertEq(tick, 0, "tick should be equal to 0");

        /* -------------------------------- tick_ > 0 ------------------------------- */
        tickSpacing = 100;
        price = 5_000_000_000 ether;
        assetPrice = 150 ether;
        longTradingExpo = 3 ether;
        accumulator = HugeUint.wrap(400_000_000_000 ether);
        tick = protocol.getEffectiveTickForPrice(price, assetPrice, longTradingExpo, accumulator, tickSpacing);
        assertEq(tick, 14_900, "tick should be equal to 345400");
    }
}

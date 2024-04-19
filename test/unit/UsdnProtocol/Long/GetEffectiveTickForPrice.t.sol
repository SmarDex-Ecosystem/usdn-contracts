// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { FixedPointMathLib } from "solady/src/utils/FixedPointMathLib.sol";

import { UsdnProtocolBaseFixture } from "test/unit/UsdnProtocol/utils/Fixtures.sol";

/// @custom:feature Test the getEffectiveTickForPrice public function of the UsdnProtocolLong contract.
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
    function test_getEffectiveTickForPrice() external {
        int24 expectedMinTick = protocol.minTick();

        /* ---------------- priceWithMultiplier = TickMath.MIN_PRICE ---------------- */
        uint256 liqMultiplier = 2000 * 10e38;
        // price = 10000 * liqMultiplier / 10e38 = 20000000
        uint128 price = 20_000_000;
        int24 minTick = protocol.getEffectiveTickForPrice(price, liqMultiplier);
        assertEq(minTick, expectedMinTick, "wrong value of minTick");

        /* ---------------- priceWithMultiplier < TickMath.MIN_PRICE ---------------- */
        liqMultiplier = 2000 * 10e38;
        // price = 9999 * liqMultiplier / 10e38 = 199998000
        price = 199_998_000;
        minTick = protocol.getEffectiveTickForPrice(price, liqMultiplier);
        assertEq(minTick, expectedMinTick, "wrong value of minTick");
    }
}

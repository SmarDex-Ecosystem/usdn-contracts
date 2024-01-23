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
    }

    /**
     * @custom:scenario Check value of the `getMinLiquidationPrice` function
     * @custom:when The price of the asset is $5000
     * @custom:and The multiplier is 1x.
     */
    function test_getMinLiquidationPrice() public {
        /**
         * 5000 - 5000 / MINIMUM_LEVERAGE = 0.000004999999995001
         * tick(0.000004999999995001) = -122100 => + tickSpacing = -122000
         * price(-122000) = 0.000005033524916457
         */

        uint256 min = protocol.getMinLiquidationPrice(5000 ether);
        assertEq(min, 0.000005033524916457 ether);
    }

    /**
     * @custom:scenario Check value of the `getMinLiquidationPrice` function
     * @custom:when The price of the asset is 10 ** 12 wei
     * @custom:and The multiplier is 1x.
     * @custom:then The minimum liquidation price should be
     * getPriceAtTick(MIN_TICK) = 10179 wei.
     */
    function test_minLiquidationPrice() public {
        uint256 minPrice = protocol.getMinLiquidationPrice(10 ** 12);
        assertEq(minPrice, TickMath.getPriceAtTick(protocol.minTick() + protocol.tickSpacing()));
    }
}

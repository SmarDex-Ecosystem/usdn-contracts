// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { FixedPointMathLib } from "solady/src/utils/FixedPointMathLib.sol";

import { UsdnProtocolBaseFixture } from "test/unit/UsdnProtocol/utils/Fixtures.sol";

import { Position } from "src/interfaces/UsdnProtocol/IUsdnProtocol.sol";

/**
 * @custom:feature The internal functions of the core of the protocol
 * @custom:background Given a protocol instance that was initialized with 2 longs and 1 short
 */
contract TestUsdnProtocolCore is UsdnProtocolBaseFixture {
    function setUp() public override {
        super.setUp();
    }

    /**
     * @custom:scenario The sum of all long position's value is equal to the long side available balance
     * @custom:given No time has elapsed since the initialization
     * @custom:and The price of the asset is equal to the initial price
     * @custom:when The sum of all position values is calculated
     * @custom:then The long side available balance is equal to the sum of all position values
     * @dev Due to imprecision in the calculations, there are in practice a few wei of difference, but always in favor
     * of the protocol (see fuzzing tests)
     */
    function test_longAssetAvailable() public {
        // calculate the value of the init position
        uint128 initLiqPrice = protocol.getEffectivePriceForTick(protocol.minTick());
        uint256 initPosValue =
            protocol.positionValue(INITIAL_PRICE, initLiqPrice, protocol.FIRST_LONG_AMOUNT(), defaultPosLeverage);

        // calculate the value of the deployer's long position
        uint128 longLiqPrice = protocol.getEffectivePriceForTick(protocol.getEffectiveTickForPrice(INITIAL_PRICE / 2));
        uint256 longPosValue = protocol.positionValue(
            INITIAL_PRICE, longLiqPrice, INITIAL_LONG - protocol.FIRST_LONG_AMOUNT(), initialLongLeverage
        );

        // calculate the sum to know the theoretical long balance
        uint256 sumOfPositions = longPosValue + initPosValue;

        // there are rounding errors when calculating the value of a position, here we have up to 1 wei of error for
        // each position, but always in favor of the protocol.
        assertGe(uint256(protocol.longAssetAvailable(INITIAL_PRICE)), sumOfPositions, "long balance");
    }
}

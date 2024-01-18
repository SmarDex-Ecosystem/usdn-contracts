// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { console2 } from "forge-std/console2.sol";

import { FixedPointMathLib } from "solady/src/utils/FixedPointMathLib.sol";

import { UsdnProtocolBaseFixture } from "test/unit/UsdnProtocol/utils/Fixtures.sol";

/**
 * @custom:feature The internal functions of the core of the protocol
 * @custom:background Given a protocol instance that was initialized
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
     * @dev Due to imprecisions in the calculations, there are in practice a few wei of difference
     * @dev TODO: can we modify the calculations so that the difference is always favoring the protocol?
     */
    function test_longAssetAvailable() public {
        // calculate the value of the init position
        uint128 initLiqPrice = protocol.getEffectivePriceForTick(protocol.minTick());
        uint256 initPosValue =
            protocol.positionValue(INITIAL_PRICE, INITIAL_PRICE, protocol.FIRST_LONG_AMOUNT(), initLiqPrice);
        emit log_named_decimal_uint("initPosValue", initPosValue, wstETH.decimals());

        // calculate the value of the deployer's long position
        uint128 longLiqPrice = protocol.getEffectivePriceForTick(protocol.getEffectiveTickForPrice(INITIAL_PRICE / 2));
        uint256 longPosValue = protocol.positionValue(
            INITIAL_PRICE, INITIAL_PRICE, INITIAL_LONG - protocol.FIRST_LONG_AMOUNT(), longLiqPrice
        );
        emit log_named_decimal_uint("longPosValue", longPosValue, wstETH.decimals());

        // calculate the sum to know the theoretical long balance
        uint256 sumOfPositions = longPosValue + initPosValue;

        // there are rounding errors when calculating the value of a position,
        // here we have up to 1 wei of error for each position
        assertApproxEqAbs(uint256(protocol.longAssetAvailable(INITIAL_PRICE)), sumOfPositions, 2, "long balance");
    }

    /**
     * @custom:scenario The sum of all long position's value is equal to the long side available balance
     * @custom:given No time has elapsed since the initialization
     * @custom:and The price of the asset has increased to $2100
     * @custom:when The sum of all position values is calculated
     * @custom:then The long side available balance is equal to the sum of all position values
     * @dev Due to imprecisions in the calculations, there are in practice a few wei of difference
     * @dev TODO: can we modify the calculations so that the difference is always favoring the protocol?
     */
    function test_longAssetAvailablePriceUp() public {
        // simulate a profit for the long (ignoring funding rates)
        uint128 currentPrice = 2100 ether;

        // calculate the value of the deployer's long position
        uint128 initLiqPrice = protocol.getEffectivePriceForTick(protocol.minTick());
        uint256 initPosValue =
            protocol.positionValue(currentPrice, INITIAL_PRICE, protocol.FIRST_LONG_AMOUNT(), initLiqPrice);
        emit log_named_decimal_uint("initPosValue", initPosValue, wstETH.decimals());

        // calculate the value of the first long position
        uint128 longLiqPrice = protocol.getEffectivePriceForTick(protocol.getEffectiveTickForPrice(INITIAL_PRICE / 2));
        uint256 longPosValue = protocol.positionValue(
            currentPrice, INITIAL_PRICE, INITIAL_LONG - protocol.FIRST_LONG_AMOUNT(), longLiqPrice
        );
        emit log_named_decimal_uint("longPosValue", longPosValue, wstETH.decimals());

        // calculate the sum to know the theoretical long balance
        uint256 sumOfPositions = longPosValue + initPosValue;

        // there are rounding errors when calculating the value of a position,
        // here we have up to 1 wei of error for each position
        assertApproxEqAbs(uint256(protocol.longAssetAvailable(currentPrice)), sumOfPositions, 1, "long balance");
    }
}

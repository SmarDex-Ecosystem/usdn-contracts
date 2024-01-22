// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { FixedPointMathLib } from "solady/src/utils/FixedPointMathLib.sol";

import { UsdnProtocolBaseFixture } from "test/unit/UsdnProtocol/utils/Fixtures.sol";

import { Position } from "src/interfaces/UsdnProtocol/IUsdnProtocol.sol";

/**
 * @custom:feature Fuzzing tests for the core of the protocol
 * @custom:background Given a protocol instance that was initialized with 2 longs and 1 short
 */
contract TestUsdnProtocolCoreFuzzing is UsdnProtocolBaseFixture {
    function setUp() public override {
        super.setUp();
    }

    /**
     * @custom:scenario The sum of all long position's value is smaller or equal to the available long balance
     * @custom:given No time has elapsed since the initialization (no funding rates)
     * @custom:and The price of the asset starts at 2000 dollars
     * @custom:and 10 random long positions and 10 random deposits are created with prices between 2000 and 3000 dollars
     * @custom:when The sum of all position values is calculated at a price between the max position start price and
     * 10000 dollars, subtracting 5 USD to simulate taking the lower bound of the confidence interval.
     * @custom:then The long side available balance is greater or equal to the sum of all position values
     * @dev If taking the same price to calculate individual position values as the overall long balance, then errors
     * will accumulate and might lead to the sum of long positions' balances exceeding the total long available assets.
     * However, since we penalize the user's position upon close by taking the lowest bound of the price confidence
     * interval given by the oracle, the protocol always win.
     * @param finalPrice the final price of the asset, at which we want to compare the available balance with the sum of
     * all long positions. 5 USD are subtracted when calculating a single long position value.
     */
    function testFuzz_longAssetAvailable(uint128 finalPrice) public {
        uint256 currentPrice = 2000 ether;

        Position[] memory pos = new Position[](10);
        int24[] memory ticks = new int24[](10);

        // create 10 random positions on each side of the protocol
        for (uint256 i = 0; i < 10; i++) {
            vm.roll(block.number + 1); // change random seed

            // create a random long position
            uint256 longAmount = (block.prevrandao % 9 ether) + 1 ether;
            uint256 longLeverage = (block.prevrandao % 3) + 2;
            uint256 longLiqPrice = currentPrice / longLeverage;
            vm.startPrank(users[i]);
            (int24 tick, uint256 index) =
                protocol.initiateOpenPosition(uint96(longAmount), uint128(longLiqPrice), abi.encode(currentPrice), "");
            protocol.validateOpenPosition(abi.encode(currentPrice), "");
            pos[i] = protocol.getLongPosition(tick, index);
            ticks[i] = tick;

            vm.roll(block.number + 1); // change random seed

            // create a random short position
            uint256 shortAmount = (block.prevrandao % 9 ether) + 1 ether;
            protocol.initiateDeposit(uint128(shortAmount), abi.encode(currentPrice), "");
            protocol.validateDeposit(abi.encode(currentPrice), "");
            vm.stopPrank();

            // increase the current price, each time by 100 dollars or less, the max price is 3000 dollars
            currentPrice += block.prevrandao % 100 ether;
        }

        // Bound the final price between the highest position start price and 10000 dollars
        finalPrice = uint128(bound(uint256(finalPrice), currentPrice, 10_000 ether));

        // calculate the value of all new long positions (simulating taking the low bound of the confidence interval)
        uint256 longPosValue;
        uint128 liqPrice;
        for (uint256 i = 0; i < 10; i++) {
            Position memory position = pos[i];
            liqPrice = protocol.getEffectivePriceForTick(
                ticks[i] - int24(protocol.liquidationPenalty()) * protocol.tickSpacing()
            );
            longPosValue += protocol.positionValue(finalPrice - 5 ether, liqPrice, position.amount, position.leverage);
        }
        // calculate the value of the init position
        liqPrice = protocol.getEffectivePriceForTick(protocol.minTick());
        longPosValue +=
            protocol.positionValue(finalPrice - 5 ether, liqPrice, protocol.FIRST_LONG_AMOUNT(), defaultPosLeverage);
        // calculate the value of the deployer's long position
        liqPrice = protocol.getEffectivePriceForTick(protocol.getEffectiveTickForPrice(INITIAL_PRICE / 2));
        longPosValue += protocol.positionValue(
            finalPrice - 5 ether, liqPrice, INITIAL_LONG - protocol.FIRST_LONG_AMOUNT(), initialLongLeverage
        );

        emit log_named_decimal_uint("longPosValue", longPosValue, wstETH.decimals());
        emit log_named_decimal_uint("long balance", uint256(protocol.longAssetAvailable(finalPrice)), wstETH.decimals());

        // The available balance should always be able to cover the value of all long positions
        assertGe(uint256(protocol.longAssetAvailable(finalPrice)), longPosValue, "long balance");
    }
}

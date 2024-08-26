// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { UsdnProtocolBaseFixture } from "../utils/Fixtures.sol";

/**
 * @custom:feature Fuzzing tests for the core of the protocol
 * @custom:background Given a protocol instance that was initialized with default params
 */
contract TestUsdnProtocolFuzzingCore is UsdnProtocolBaseFixture {
    struct TestData {
        uint256 currentPrice;
        int24 firstPosTick;
        Position firstPos;
        uint256 longPosValue;
    }

    function setUp() public {
        params = DEFAULT_PARAMS;
        params.flags.enableFunding = false;
        params.flags.enableProtocolFees = false;
        super._setUp(DEFAULT_PARAMS);
    }

    /**
     * @custom:scenario The sum of all long position's value is smaller or equal to the available long balance
     * @custom:given No time has elapsed since the initialization (no funding)
     * @custom:and The price of the asset starts at 2000 dollars
     * @custom:and 10 random long positions and 10 random deposits are created with prices between 2000 and 3000 dollars
     * @custom:when The sum of all position values is calculated at a price between the max position start price and
     * 10000 dollars.
     * @custom:then The long side available balance is greater or equal to the sum of all position values
     * @param finalPrice the final price of the asset, at which we want to compare the available balance with the sum of
     * all long positions.
     * @param random a random number used to generate the position parameters
     */
    function testFuzz_longAssetAvailable(uint128 finalPrice, uint256 random) public {
        TestData memory data;
        data.currentPrice = 2000 ether;

        data.firstPosTick = protocol.getHighestPopulatedTick();
        (data.firstPos,) = protocol.getLongPosition(PositionId(data.firstPosTick, 0, 0));

        Position[] memory pos = new Position[](10);
        int24[] memory ticks = new int24[](10);
        uint256[] memory indices = new uint256[](10);

        // create 10 random positions on each side of the protocol
        for (uint256 i = 0; i < 10; i++) {
            random = uint256(keccak256(abi.encode(random, i)));
            uint256 longAmount;
            uint256 longLiqPrice;
            {
                longAmount = (random % 9 ether) + 1 ether;
                uint256 longLeverage = (random % 3) + 2;
                longLiqPrice = data.currentPrice / longLeverage;
            }

            // create a random user with ~8.5K wstETH
            address user;
            {
                user = vm.addr(i + 1);
                vm.deal(user, 20_000 ether);
                vm.startPrank(user);
                (bool success,) = address(wstETH).call{ value: 10_000 ether }("");
                require(success, "wstETH mint failed");
            }
            PositionId memory posId = setUpUserPositionInLong(
                OpenParams({
                    user: user,
                    untilAction: ProtocolAction.ValidateOpenPosition,
                    positionSize: uint128(longAmount),
                    desiredLiqPrice: uint128(longLiqPrice),
                    price: data.currentPrice
                })
            );
            (pos[i],) = protocol.getLongPosition(posId);
            ticks[i] = posId.tick;
            indices[i] = posId.index;

            random = uint256(keccak256(abi.encode(random, i, 2)));

            // create a random deposit position
            uint256 depositAmount = (random % 9 ether) + 1 ether;
            setUpUserPositionInVault(user, ProtocolAction.ValidateDeposit, uint128(depositAmount), data.currentPrice);
            vm.stopPrank();

            // increase the current price, each time by 100 dollars or less, the max price is 3000 dollars
            data.currentPrice += random % 100 ether;
        }

        skip(1 hours);

        // Bound the final price between the highest position start price and 10000 dollars
        finalPrice = uint128(bound(uint256(finalPrice), data.currentPrice, 10_000 ether));

        // calculate the value of all new long positions
        uint256 longPosValue;
        for (uint256 i = 0; i < 10; i++) {
            longPosValue += uint256(
                protocol.getPositionValue(PositionId(ticks[i], 0, indices[i]), finalPrice, uint128(block.timestamp))
            );
        }

        // calculate the value of the deployer's long position
        uint128 liqPrice = protocol.getEffectivePriceForTick(data.firstPosTick);

        longPosValue += uint256(protocol.i_positionValue(finalPrice, liqPrice, data.firstPos.totalExpo));

        // The available balance should always be able to cover the value of all long positions
        assertGe(uint256(protocol.i_longAssetAvailable(finalPrice)), longPosValue, "long balance");
    }
}

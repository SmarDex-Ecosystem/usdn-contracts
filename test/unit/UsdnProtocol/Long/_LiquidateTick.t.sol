// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { UsdnProtocolBaseFixture } from "test/unit/UsdnProtocol/utils/Fixtures.sol";

import { ProtocolAction } from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";

/// @custom:feature Test the _liquidateTick internal function of the long layer
contract TestUsdnProtocolLongLiquidateTick is UsdnProtocolBaseFixture {
    function setUp() public {
        super._setUp(DEFAULT_PARAMS);
    }

    /**
     * @custom:scenario Liquidate a tick at a certain price
     * @custom:given A tick with assets in it
     * @custom:when User calls _liquidateTick
     * @custom:then It should liquidate the tick.
     */
    function test_liquidateTick() public {
        uint128 price = 2000 ether;

        // Create a long position to liquidate
        (int24 tick, uint256 tickVersion,) = setUpUserPositionInLong(
            address(this), ProtocolAction.ValidateOpenPosition, 1 ether, price - 200 ether, price
        );

        uint128 liqPrice = protocol.getEffectivePriceForTick(tick);

        uint256 bitmapIndexBefore = protocol.findLastSetInTickBitmap(tick);
        uint256 positionsCountBefore = protocol.getTotalLongPositions();
        uint256 totalExpoInTick = protocol.getTotalExpoByTick(tick);
        uint256 totalExpoBefore = protocol.getTotalExpo();
        uint128 liqPriceAfterFundings = protocol.getEffectivePriceForTick(tick, protocol.getLiquidationMultiplier());

        // Calculate the collateral this position gives on liquidation
        int256 tickValue = protocol.i_tickValue(liqPrice, tick, protocol.getTotalExpoByTick(tick));

        vm.expectEmit();
        emit LiquidatedTick(tick, tickVersion, liqPrice, liqPriceAfterFundings, tickValue);
        int256 collateralLiquidated = protocol.i_liquidateTick(tick, protocol.tickHash(tick, tickVersion), liqPrice);

        assertEq(
            positionsCountBefore - 1, protocol.getTotalLongPositions(), "Only one position should have been liquidated"
        );
        assertEq(tickVersion + 1, protocol.getTickVersion(tick), "The version of the tick should have been incremented");
        assertEq(collateralLiquidated, tickValue, "Collateral liquidated should be equal to tickValue");
        assertEq(
            totalExpoBefore,
            protocol.getTotalExpo() + totalExpoInTick,
            "The total expo in the liquidated tick should have been subtracted from the global total expo"
        );
        assertLt(protocol.findLastSetInTickBitmap(tick), bitmapIndexBefore, "The last set for the tick should be lower");
    }
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { USER_1 } from "../../../utils/Constants.sol";
import { UsdnProtocolBaseFixture } from "../utils/Fixtures.sol";

import { HugeUint } from "../../../../src/libraries/HugeUint.sol";
import { TickMath } from "../../../../src/libraries/TickMath.sol";

/**
 * @custom:feature The _saveNewPosition internal function of the UsdnProtocolLong contract.
 * @custom:background Given a protocol initialized with 10 wstETH in the vault and 5 wstETH in a long position with a
 * leverage of ~2x
 */
contract TestUsdnProtocolLongSaveNewPosition is UsdnProtocolBaseFixture {
    using HugeUint for HugeUint.Uint512;

    uint128 internal constant LONG_AMOUNT = 1 ether;
    uint128 internal constant CURRENT_PRICE = 2000 ether;

    Position long = Position({
        validated: false,
        user: USER_1,
        amount: LONG_AMOUNT,
        totalExpo: LONG_AMOUNT * 3,
        timestamp: uint40(block.timestamp)
    });

    function setUp() public {
        super._setUp(DEFAULT_PARAMS);
        wstETH.mintAndApprove(address(this), 10 ether, address(protocol), type(uint256).max);
    }

    /**
     * @custom:scenario Test that the function returns the expected information
     * @custom:given A validated long position
     * @custom:when The function is called with the new position
     * @custom:then The function should return the expected information
     */
    function test_saveNewPosition() public {
        uint128 desiredLiqPrice = CURRENT_PRICE * 2 / 3; // leverage approx 3x
        int24 expectedTick = protocol.getEffectiveTickForPrice(desiredLiqPrice);
        uint24 liquidationPenalty = protocol.getTickLiquidationPenalty(expectedTick);
        HugeUint.Uint512 memory initialLiqMultiplierAccumulator = protocol.getLiqMultiplierAccumulator();
        uint256 unadjustedTickPrice =
            TickMath.getPriceAtTick(protocol.i_calcTickWithoutPenalty(expectedTick, liquidationPenalty));

        HugeUint.Uint512 memory expectedLiqMultiplierAccumulator =
            initialLiqMultiplierAccumulator.add(HugeUint.wrap(unadjustedTickPrice * long.totalExpo));

        (uint256 tickVersion, uint256 index, HugeUint.Uint512 memory liqMultiplierAccumulator) =
            protocol.i_saveNewPosition(expectedTick, long, liquidationPenalty);

        assertEq(tickVersion, 0, "tick version");
        assertEq(index, 0, "index");
        assertEq(liqMultiplierAccumulator.hi, expectedLiqMultiplierAccumulator.hi, "liqMultiplierAccumulator hi");
        assertEq(liqMultiplierAccumulator.lo, expectedLiqMultiplierAccumulator.lo, "liqMultiplierAccumulator lo");
    }

    /**
     * @custom:scenario Test that the function save new position
     * @custom:given A validated long position
     * @custom:when The function is called with the new position
     * @custom:then The position should be created on the expected tick
     * @custom:and The protocol's state should be updated
     */
    function test_saveNewPositionState() public {
        uint128 desiredLiqPrice = CURRENT_PRICE * 2 / 3; // leverage approx 3x
        int24 expectedTick = protocol.getEffectiveTickForPrice(desiredLiqPrice);

        // state before opening the position
        uint256 balanceLongBefore = uint256(protocol.i_longAssetAvailable(CURRENT_PRICE));
        uint256 totalExpoBefore = protocol.getTotalExpo();
        TickData memory tickDataBefore = protocol.getTickData(expectedTick);
        uint256 totalPositionsBefore = protocol.getTotalLongPositions();

        protocol.i_saveNewPosition(expectedTick, long, protocol.getTickLiquidationPenalty(expectedTick));

        (Position memory positionInTick,) =
            protocol.getLongPosition(PositionId(expectedTick, 0, tickDataBefore.totalPos));

        // state after opening the position
        assertEq(balanceLongBefore, protocol.getBalanceLong(), "balance of long side");
        assertEq(totalExpoBefore + LONG_AMOUNT * 3, protocol.getTotalExpo(), "total expo");
        TickData memory tickDataAfter = protocol.getTickData(expectedTick);
        assertEq(tickDataBefore.totalExpo + LONG_AMOUNT * 3, tickDataAfter.totalExpo, "total expo in tick");
        assertEq(tickDataBefore.totalPos + 1, tickDataAfter.totalPos, "positions in tick");
        assertEq(totalPositionsBefore + 1, protocol.getTotalLongPositions(), "total long positions");

        // check the last position in the tick
        assertEq(long.user, positionInTick.user, "last long in tick: user");
        assertEq(long.amount, positionInTick.amount, "last long in tick: amount");
        assertEq(long.totalExpo, positionInTick.totalExpo, "last long in tick: totalExpo");
        assertEq(long.timestamp, positionInTick.timestamp, "last long in tick: timestamp");
    }

    /**
     * @custom:scenario Save a new position at a higher tick than the current highest populated tick
     * @custom:given A validated long position
     * @custom:when The function is called with the new position
     * @custom:then The highest populated tick is updated
     * @custom:and The new position is the first one in the tick bitmap
     */
    function test_saveNewPositionAtHigherThanHighestTick() public {
        uint128 desiredLiqPrice = CURRENT_PRICE * 2 / 3; // leverage approx 3x
        int24 expectedTick = protocol.getEffectiveTickForPrice(desiredLiqPrice);

        // state modified by condition before opening the position
        uint256 tickBitmapIndexBefore = protocol.findLastSetInTickBitmap(expectedTick);
        int24 highestPopulatedTickBefore = protocol.getHighestPopulatedTick();

        vm.expectEmit();
        emit HighestPopulatedTickUpdated(expectedTick);
        protocol.i_saveNewPosition(expectedTick, long, protocol.getTickLiquidationPenalty(expectedTick));
        uint256 tickBitmapIndexAfter = protocol.findLastSetInTickBitmap(expectedTick);
        int24 highestPopulatedTickAfter = protocol.getHighestPopulatedTick();

        // check state modified by condition after opening the position
        assertLt(tickBitmapIndexBefore, tickBitmapIndexAfter, "first position in this tick");
        assertLt(
            highestPopulatedTickBefore, highestPopulatedTickAfter, "highest populated tick should be higher than before"
        );
        assertEq(highestPopulatedTickAfter, expectedTick, "highest populated tick should be the expected tick");

        protocol.i_saveNewPosition(expectedTick, long, protocol.getTickLiquidationPenalty(expectedTick));

        // state not modified by condition after opening the position
        assertEq(tickBitmapIndexAfter, protocol.findLastSetInTickBitmap(expectedTick), "second position in this tick");
    }
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { UsdnProtocolBaseFixture } from "test/unit/UsdnProtocol/utils/Fixtures.sol";
import { USER_1 } from "test/utils/Constants.sol";

import { Position } from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";

/**
 * @custom:feature The _saveNewPosition internal function of the UsdnProtocolLong contract.
 * @custom:background Given a protocol initialized with 10 wstETH in the vault and 5 wstETH in a long position with a
 * leverage of ~2x
 */
contract TestUsdnProtocolLongSaveNewPosition is UsdnProtocolBaseFixture {
    uint256 internal constant LONG_AMOUNT = 1 ether;
    uint128 internal constant CURRENT_PRICE = 2000 ether;

    Position long = Position({
        user: USER_1,
        amount: uint128(LONG_AMOUNT),
        totalExpo: uint128(LONG_AMOUNT) * 3,
        timestamp: uint40(block.timestamp)
    });

    function setUp() public {
        super._setUp(DEFAULT_PARAMS);
        wstETH.mintAndApprove(address(this), 10 ether, address(protocol), type(uint256).max);
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
        uint256 totalExpoInTickBefore = protocol.getCurrentTotalExpoByTick(expectedTick);
        uint256 positionsInTickBefore = protocol.getCurrentPositionsInTick(expectedTick);
        uint256 totalPositionsBefore = protocol.getTotalLongPositions();

        protocol.i_saveNewPosition(expectedTick, long);

        Position memory positionInTick = protocol.getLongPosition(expectedTick, 0, positionsInTickBefore);

        // state after opening the position
        assertEq(balanceLongBefore + LONG_AMOUNT, protocol.getBalanceLong(), "balance of long side");
        assertEq(totalExpoBefore + uint128(LONG_AMOUNT) * 3, protocol.getTotalExpo(), "total expo");
        assertEq(
            totalExpoInTickBefore + uint128(LONG_AMOUNT) * 3,
            protocol.getCurrentTotalExpoByTick(expectedTick),
            "total expo in tick"
        );
        assertEq(positionsInTickBefore + 1, protocol.getPositionsInTick(expectedTick), "positions in tick");
        assertEq(totalPositionsBefore + 1, protocol.getTotalLongPositions(), "total long positions");

        // check the last position in the tick
        assertEq(long.user, positionInTick.user, "last long in tick: user");
        assertEq(long.amount, positionInTick.amount, "last long in tick: amount");
        assertEq(long.totalExpo, positionInTick.totalExpo, "last long in tick: totalExpo");
        assertEq(long.timestamp, positionInTick.timestamp, "last long in tick: timestamp");
    }

    /**
     * @custom:scenario Test that the function save new position and modify the
     * state in conditions(tickBitmap and maxInitializedTick)
     * @custom:given A validated long position
     * @custom:when The function is called with the new position
     * @custom:then The state in conditions should be modified
     */
    function test_saveNewPositionConditions() public {
        uint128 desiredLiqPrice = CURRENT_PRICE * 2 / 3; // leverage approx 3x
        int24 expectedTick = protocol.getEffectiveTickForPrice(desiredLiqPrice);

        // state modified by condition before opening the position
        uint256 tickBitmapIndexBefore = protocol.findLastSetInTickBitmap(expectedTick);
        int24 maxInitializedTickBefore = protocol.getMaxInitializedTick();

        protocol.i_saveNewPosition(protocol.getEffectiveTickForPrice(desiredLiqPrice), long);
        uint256 tickBitmapIndexAfter = protocol.findLastSetInTickBitmap(expectedTick);
        int24 initializedTickAfter = protocol.getMaxInitializedTick();

        // check state modified by condition after opening the position
        assertNotEq(tickBitmapIndexBefore, tickBitmapIndexAfter, "first position in this tick");
        assertLt(maxInitializedTickBefore, initializedTickAfter, "max initialized tick");

        protocol.i_saveNewPosition(protocol.getEffectiveTickForPrice(desiredLiqPrice), long);

        // state not modified by condition after opening the position
        assertEq(tickBitmapIndexAfter, protocol.findLastSetInTickBitmap(expectedTick), "second position in this tick");
        assertEq(initializedTickAfter, protocol.getMaxInitializedTick(), "second position max initialized tick");
    }
}

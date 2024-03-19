// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { UsdnProtocolBaseFixture } from "test/unit/UsdnProtocol/utils/Fixtures.sol";

import { Position, ProtocolAction } from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";

/**
 * @custom:feature The _removeAmountFromPosition internal function of the UsdnProtocolActions contract.
 * @custom:background Given a protocol initialized with 10 wstETH in the vault and 5 wstETH in a long position with a
 * leverage of ~2x
 * @custom:and a validated long position of 1 ether with 10x leverage
 */
contract TestUsdnProtocolLongRemoveAmountFromPosition is UsdnProtocolBaseFixture {
    int24 private _tick;
    uint256 private _tickVersion;
    uint256 private _index;
    uint128 private _positionAmount = 1 ether;

    function setUp() external {
        _setUp(DEFAULT_PARAMS);

        wstETH.mintAndApprove(address(this), 100_000 ether, address(protocol), type(uint256).max);
        (_tick, _tickVersion, _index) = setUpUserPositionInLong(
            address(this),
            ProtocolAction.ValidateOpenPosition,
            _positionAmount,
            params.initialPrice - (params.initialPrice / 5),
            params.initialPrice
        );
    }

    /**
     * @custom:scenario A user wants to remove the full amount from a position
     * @custom:given A validated long position
     * @custom:when User calls _removeAmountFromPosition with the full position amount
     * @custom:then The position should be deleted from the tick array
     * @custom:and the protocol's state should be updated
     */
    function test_removeAmountFromPosition_removingEverythingDeletesThePosition() external {
        Position memory posBefore = protocol.getLongPosition(_tick, _tickVersion, _index);
        uint256 bitmapIndexBefore = protocol.findLastSetInTickBitmap(_tick);
        uint256 totalExpoBefore = protocol.getTotalExpo();
        uint256 totalExpoByTickBefore = protocol.getTotalExpoByTick(_tick, _tickVersion);
        uint256 positionsCountBefore = protocol.getLongPositionsLength(_tick);
        protocol.i_removeAmountFromPosition(_tick, _tickVersion, posBefore, posBefore.amount, posBefore.totalExpo);

        /* ----------------------------- Position State ----------------------------- */
        Position memory posAfter = protocol.getLongPosition(_tick, _tickVersion, _index);
        assertEq(posAfter.user, address(0), "Address of the position should have been reset");
        assertEq(posAfter.timestamp, 0, "Timestamp of the position should have been reset");
        assertEq(posAfter.totalExpo, 0, "Total expo of the position should have been reset");
        assertEq(posAfter.amount, 0, "Amount of the position should have been reset");

        /* ----------------------------- Protocol State ----------------------------- */
        assertEq(
            positionsCountBefore - 1, protocol.getLongPositionsLength(_tick), "The position should have been removed"
        );
        assertGt(
            bitmapIndexBefore - protocol.findLastSetInTickBitmap(_tick), 0, "The last bitmap index should have changed"
        );
        assertEq(
            totalExpoBefore - protocol.getTotalExpo(),
            posBefore.totalExpo,
            "The total expo of the position should have been subtracted from the total expo of the protocol"
        );
        assertEq(
            totalExpoByTickBefore - protocol.getTotalExpoByTick(_tick, _tickVersion),
            posBefore.totalExpo,
            "The total expo of the position should have been subtracted from the total expo of the tick"
        );
    }

    /**
     * @custom:scenario A user wants to remove the some amount from a position
     * @custom:given A validated long position
     * @custom:when User calls _removeAmountFromPosition with the half the amount of a position
     * @custom:then The position should be updated
     * @custom:and the protocol's state should be updated
     */
    function test_removeAmountFromPosition_removingSomeAmountUpdatesThePosition() external {
        Position memory posBefore = protocol.getLongPosition(_tick, _tickVersion, _index);
        uint256 bitmapIndexBefore = protocol.findLastSetInTickBitmap(_tick);
        uint256 totalExpoBefore = protocol.getTotalExpo();
        uint256 totalExpoByTickBefore = protocol.getTotalExpoByTick(_tick, _tickVersion);
        uint256 positionsCountBefore = protocol.getLongPositionsLength(_tick);
        uint128 amountToRemove = posBefore.amount / 2;
        uint128 totalExpoToRemove = protocol.i_calculatePositionTotalExpo(
            amountToRemove, params.initialPrice, params.initialPrice - (params.initialPrice / 5)
        );

        protocol.i_removeAmountFromPosition(_tick, _tickVersion, posBefore, amountToRemove, totalExpoToRemove);

        /* ----------------------------- Position State ----------------------------- */
        Position memory posAfter = protocol.getLongPosition(_tick, _tickVersion, _index);
        assertEq(posAfter.user, posBefore.user, "Address of the position should not have changed");
        assertEq(posAfter.timestamp, posBefore.timestamp, "Timestamp of the position should not have changed");
        assertEq(
            posAfter.totalExpo,
            posBefore.totalExpo - totalExpoToRemove,
            "Expo to remove should have been subtracted from the total expo of the position"
        );
        assertEq(
            posAfter.amount,
            posBefore.amount - amountToRemove,
            "amount to remove should have been subtracted from the amount of the position"
        );

        /* ----------------------------- Protocol State ----------------------------- */
        assertEq(
            positionsCountBefore,
            protocol.getLongPositionsLength(_tick),
            "The number of positions should not have changed"
        );
        assertEq(
            bitmapIndexBefore - protocol.findLastSetInTickBitmap(_tick), 0, "The last bitmap index should be the same"
        );
        assertEq(
            totalExpoBefore - totalExpoToRemove,
            protocol.getTotalExpo(),
            "The total expo to remove should have been subtracted from the total expo of the protocol"
        );
        assertEq(
            totalExpoByTickBefore - totalExpoToRemove,
            protocol.getTotalExpoByTick(_tick, _tickVersion),
            "The total expo to remove should have been subtracted from the total expo of the tick"
        );
    }
}

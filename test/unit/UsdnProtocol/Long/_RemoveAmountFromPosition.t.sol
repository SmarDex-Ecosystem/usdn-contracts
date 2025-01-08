// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { HugeUint } from "@smardex-solidity-libraries-1/HugeUint.sol";

import { UsdnProtocolBaseFixture } from "../utils/Fixtures.sol";

import { TickMath } from "../../../../src/libraries/TickMath.sol";

/**
 * @custom:feature The _removeAmountFromPosition internal function of the UsdnProtocolActions contract.
 * @custom:background Given a protocol initialized with 10 wstETH in the vault and 5 wstETH in a long position with a
 * leverage of ~2x
 * @custom:and a validated long position of 1 ether with 10x leverage
 */
contract TestUsdnProtocolLongRemoveAmountFromPosition is UsdnProtocolBaseFixture {
    using HugeUint for HugeUint.Uint512;

    PositionId private _posId;
    uint128 private _positionAmount = 1 ether;

    function setUp() public {
        _setUp(DEFAULT_PARAMS);

        wstETH.mintAndApprove(address(this), 100_000 ether, address(protocol), type(uint256).max);
        _posId = setUpUserPositionInLong(
            OpenParams({
                user: address(this),
                untilAction: ProtocolAction.ValidateOpenPosition,
                positionSize: _positionAmount,
                desiredLiqPrice: params.initialPrice - (params.initialPrice / 5),
                price: params.initialPrice
            })
        );
    }

    /**
     * @custom:scenario A user wants to remove the full amount from a position
     * @custom:given A validated long position
     * @custom:when User calls _removeAmountFromPosition with the full position amount
     * @custom:then The position should be deleted from the tick array
     * @custom:and the protocol's state should be updated
     */
    function test_removeAmountFromPosition_removingEverythingDeletesThePosition() public {
        (Position memory posBefore,) = protocol.getLongPosition(_posId);
        uint256 bitmapIndexBefore = protocol.findLastSetInTickBitmap(_posId.tick);
        uint256 totalExpoBefore = protocol.getTotalExpo();
        HugeUint.Uint512 memory liqMultiplierAccBefore = protocol.getLiqMultiplierAccumulator();
        TickData memory tickData = protocol.getTickData(_posId.tick);
        (HugeUint.Uint512 memory liqMultiplierAcc) = protocol.i_removeAmountFromPosition(
            _posId.tick, _posId.tickVersion, posBefore, posBefore.amount, posBefore.totalExpo
        );

        assertEq(
            keccak256(abi.encode(liqMultiplierAcc)),
            keccak256(abi.encode(protocol.getLiqMultiplierAccumulator())),
            "The returned liquidation multiplier accumulator should be equal to the one in storage"
        );
        uint256 unadjustedTickPrice =
            TickMath.getPriceAtTick(protocol.i_calcTickWithoutPenalty(_posId.tick, tickData.liquidationPenalty));
        assertEq(
            liqMultiplierAccBefore.lo - (unadjustedTickPrice * posBefore.totalExpo),
            liqMultiplierAcc.lo,
            "The returned liquidation multiplier accumulator should have been updated"
        );
        assertEq(
            liqMultiplierAccBefore.hi, liqMultiplierAcc.hi, "The high part of the multiplier should not have changed"
        );

        /* ----------------------------- Position State ----------------------------- */
        TickData memory newTickData = protocol.getTickData(_posId.tick);
        (Position memory posAfter,) = protocol.getLongPosition(_posId);
        assertEq(posAfter.user, address(0), "Address of the position should have been reset");
        assertEq(posAfter.timestamp, 0, "Timestamp of the position should have been reset");
        assertEq(posAfter.totalExpo, 0, "Total expo of the position should have been reset");
        assertEq(posAfter.amount, 0, "Amount of the position should have been reset");

        /* ----------------------------- Protocol State ----------------------------- */
        assertEq(tickData.totalPos - 1, newTickData.totalPos, "The position should have been removed");
        assertGt(
            bitmapIndexBefore - protocol.findLastSetInTickBitmap(_posId.tick),
            0,
            "The last bitmap index should have changed"
        );
        assertEq(
            totalExpoBefore - protocol.getTotalExpo(),
            posBefore.totalExpo,
            "The total expo of the position should have been subtracted from the total expo of the protocol"
        );
        assertEq(
            tickData.totalExpo - newTickData.totalExpo,
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
    function test_removeAmountFromPosition_removingSomeAmountUpdatesThePosition() public {
        (Position memory posBefore,) = protocol.getLongPosition(_posId);
        uint256 bitmapIndexBefore = protocol.findLastSetInTickBitmap(_posId.tick);
        uint256 totalExpoBefore = protocol.getTotalExpo();
        HugeUint.Uint512 memory liqMultiplierAccBefore = protocol.getLiqMultiplierAccumulator();
        TickData memory tickData = protocol.getTickData(_posId.tick);
        uint128 amountToRemove = posBefore.amount / 2;
        uint128 totalExpoToRemove = protocol.i_calcPositionTotalExpo(
            amountToRemove, params.initialPrice, params.initialPrice - (params.initialPrice / 5)
        );

        (HugeUint.Uint512 memory liqMultiplierAcc) = protocol.i_removeAmountFromPosition(
            _posId.tick, _posId.tickVersion, posBefore, amountToRemove, totalExpoToRemove
        );

        assertEq(
            abi.encode(liqMultiplierAcc),
            abi.encode(protocol.getLiqMultiplierAccumulator()),
            "The returned liquidation multiplier accumulator should be equal to the one in storage"
        );
        uint256 unadjustedTickPrice =
            TickMath.getPriceAtTick(protocol.i_calcTickWithoutPenalty(_posId.tick, tickData.liquidationPenalty));
        assertEq(
            liqMultiplierAccBefore.lo - (unadjustedTickPrice * totalExpoToRemove),
            liqMultiplierAcc.lo,
            "The returned liquidation multiplier accumulator should have been updated"
        );
        assertEq(
            liqMultiplierAccBefore.hi, liqMultiplierAcc.hi, "The high part of the multiplier should not have changed"
        );

        /* ----------------------------- Position State ----------------------------- */
        TickData memory newTickData = protocol.getTickData(_posId.tick);
        (Position memory posAfter,) = protocol.getLongPosition(_posId);
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
        assertEq(tickData.totalPos, newTickData.totalPos, "The number of positions should not have changed");
        assertEq(
            bitmapIndexBefore - protocol.findLastSetInTickBitmap(_posId.tick),
            0,
            "The last bitmap index should be the same"
        );
        assertEq(
            totalExpoBefore - totalExpoToRemove,
            protocol.getTotalExpo(),
            "The total expo to remove should have been subtracted from the total expo of the protocol"
        );
        assertEq(
            tickData.totalExpo - totalExpoToRemove,
            newTickData.totalExpo,
            "The total expo to remove should have been subtracted from the total expo of the tick"
        );
    }
}

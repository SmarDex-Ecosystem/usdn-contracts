// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { ADMIN } from "../../../utils/Constants.sol";
import { UsdnProtocolBaseFixture } from "../utils/Fixtures.sol";

import { HugeUint } from "../../../../src/libraries/HugeUint.sol";

/**
 * @custom:feature The `_flashOpenPosition` internal function of the UsdnProtocolLong contract
 * @custom:background Given a protocol initialized with default params
 * @custom:and A current price of 2000USD, a vault balance of 200 ether, a long balance of 100 ether
 * @custom:and A total expo of 300 ether and an amount of 1 ether
 */
contract TestUsdnProtocolLongFlashOpenPosition is UsdnProtocolBaseFixture {
    uint128 constant CURRENT_PRICE = 2000 ether;
    uint128 constant BALANCE_VAULT = 200 ether;
    uint128 constant BALANCE_LONG = 100 ether;
    uint128 constant TOTAL_EXPO = 300 ether;
    uint128 constant AMOUNT = 1 ether;
    uint128 longTradingExpo = TOTAL_EXPO - BALANCE_LONG;
    HugeUint.Uint512 liqMultiplierAccumulator;

    function setUp() public {
        super._setUp(DEFAULT_PARAMS);
    }

    /**
     * @custom:scenario Flash opening a position
     * @custom:when _flashOpenPosition is called
     * @custom:then A new position is opened
     * @custom:and InitiatedOpenPosition and ValidatedOpenPosition events are emitted
     */
    function test_flashOpenPosition() public {
        int24 tickWithoutPenalty = protocol.getEffectiveTickForPrice(
            1500 ether, CURRENT_PRICE, longTradingExpo, liqMultiplierAccumulator, _tickSpacing
        );
        uint128 tickPriceWithoutPenalty = protocol.getEffectivePriceForTick(
            tickWithoutPenalty, CURRENT_PRICE, longTradingExpo, liqMultiplierAccumulator
        );
        int24 tick = tickWithoutPenalty + int24(uint24(protocol.getLiquidationPenalty())) * _tickSpacing;
        uint128 positionTotalExpo = protocol.i_calcPositionTotalExpo(AMOUNT, CURRENT_PRICE, tickPriceWithoutPenalty);
        uint256 longPositionsCountBefore = protocol.getTotalLongPositions();

        _expectEmit(positionTotalExpo, PositionId(tick, 0, 0));
        (PositionId memory posId) = protocol.i_flashOpenPosition(
            address(this),
            CURRENT_PRICE,
            tickWithoutPenalty,
            AMOUNT,
            TOTAL_EXPO,
            BALANCE_LONG,
            BALANCE_VAULT,
            liqMultiplierAccumulator
        );

        assertEq(posId.tick, tick, "The tick should be the expected tick");
        (Position memory pos,) = protocol.getLongPosition(posId);
        assertEq(pos.timestamp, block.timestamp, "the timestamp should be equal to now");
        assertEq(pos.user, address(this), "The user should be the provided address");
        assertEq(pos.totalExpo, positionTotalExpo, "The total expo should be equal to the expected one");
        assertEq(pos.amount, AMOUNT, "The amount should be equal to the provided one");

        assertEq(
            longPositionsCountBefore + 1, protocol.getTotalLongPositions(), "A long position should have been created"
        );
    }

    /**
     * @custom:scenario Flash opening a position on a tick with a different liquidation penalty
     * @custom:given The liquidation penalty was updated
     * @custom:when _flashOpenPosition is called with a tick that already had a position before the penalty change
     * @custom:then A new position is opened
     * @custom:and InitiatedOpenPosition and ValidatedOpenPosition events are emitted
     * @custom:and The created position has the same penalty as the positions in the tick
     */
    function test_flashOpenPositionOnTickWithDifferentPenalty() public {
        int24 tickWithoutOldPenalty =
            initialPosition.tick - int24(uint24(protocol.getLiquidationPenalty())) * _tickSpacing;
        int24 tickWithoutNewPenalty = initialPosition.tick - _tickSpacing;
        uint128 tickPriceWithoutOldPenalty = protocol.getEffectivePriceForTick(
            tickWithoutOldPenalty, CURRENT_PRICE, longTradingExpo, liqMultiplierAccumulator
        );
        uint128 positionTotalExpo = protocol.i_calcPositionTotalExpo(AMOUNT, CURRENT_PRICE, tickPriceWithoutOldPenalty);
        uint256 longPositionsCountBefore = protocol.getTotalLongPositions();

        vm.prank(ADMIN);
        protocol.setLiquidationPenalty(1);

        _expectEmit(positionTotalExpo, PositionId(initialPosition.tick, 0, 1));
        (PositionId memory posId) = protocol.i_flashOpenPosition(
            address(this),
            CURRENT_PRICE,
            tickWithoutNewPenalty,
            AMOUNT,
            TOTAL_EXPO,
            BALANCE_LONG,
            BALANCE_VAULT,
            liqMultiplierAccumulator
        );

        assertEq(
            longPositionsCountBefore + 1, protocol.getTotalLongPositions(), "A long position should have been created"
        );
        assertEq(posId.tick, initialPosition.tick, "The returned tick should be the initial position tick");
        assertEq(
            posId.index, initialPosition.index + 1, "The position should be in the same tick as the initial position"
        );

        (Position memory pos,) = protocol.getLongPosition(posId);
        assertEq(pos.timestamp, block.timestamp, "the timestamp should be equal to now");
        assertEq(pos.user, address(this), "The user should be the provided address");
        assertEq(pos.totalExpo, positionTotalExpo, "The total expo should be equal to the expected one");
        assertEq(pos.amount, AMOUNT, "The amount should be equal to the provided one");
    }

    function _expectEmit(uint128 positionTotalExpo, PositionId memory posId) internal {
        vm.expectEmit();
        emit InitiatedOpenPosition(
            address(this), address(this), uint40(block.timestamp), positionTotalExpo, AMOUNT, CURRENT_PRICE, posId
        );
        vm.expectEmit();
        emit ValidatedOpenPosition(address(this), address(this), positionTotalExpo, CURRENT_PRICE, posId);
    }
}

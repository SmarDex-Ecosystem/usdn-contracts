// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { ADMIN, USER_1 } from "../../../utils/Constants.sol";
import { UsdnProtocolBaseFixture } from "../utils/Fixtures.sol";

/**
 * @custom:feature Test of the protocol `_prepareValidateOpenPositionData` internal function
 * @custom:background Given a protocol with a long position that needs to be validated
 */
contract TestUsdnProtocolActionsPrepareValidateOpenPositionData is UsdnProtocolBaseFixture {
    uint128 private constant POSITION_AMOUNT = 0.1 ether;
    PositionId private posId;
    uint128 private liqPriceWithoutPenalty;
    bytes private currentPriceData;
    uint40 private timestampAtInitiate;
    PendingAction private pendingAction;

    function setUp() public {
        super._setUp(DEFAULT_PARAMS);

        wstETH.mintAndApprove(address(this), 100 ether, address(protocol), type(uint256).max);
        wstETH.mintAndApprove(USER_1, 100 ether, address(protocol), type(uint256).max);

        currentPriceData = abi.encode(params.initialPrice);
        (, posId) = protocol.initiateOpenPosition(
            POSITION_AMOUNT,
            params.initialPrice * 2 / 3,
            type(uint128).max,
            protocol.getMaxLeverage(),
            address(this),
            payable(address(this)),
            type(uint256).max,
            currentPriceData,
            EMPTY_PREVIOUS_DATA
        );

        liqPriceWithoutPenalty = protocol.getEffectivePriceForTick(protocol.i_calcTickWithoutPenalty(posId.tick));
        (pendingAction,) = protocol.i_getPendingAction(address(this));
        timestampAtInitiate = uint40(block.timestamp);
    }

    /**
     * @custom:scenario _prepareValidateOpenPositionData is called at the same price as the position's start price
     * @custom:given The price did not change between the open and the call
     * @custom:when _prepareValidateOpenPositionData is called
     * @custom:then The matching data is returned
     * @custom:and The position should not have been liquidated
     */
    function test_prepareValidateOpenPositionData() public {
        _waitDelay();

        (ValidateOpenPositionData memory data, bool liquidated) =
            protocol.i_prepareValidateOpenPositionData(pendingAction, currentPriceData);

        assertFalse(liquidated, "The position should not have been liquidated");
        assertFalse(data.isLiquidationPending, "There should be no pending liquidation");
        _assertData(data, false);
    }

    /**
     * @custom:scenario _prepareValidateOpenPositionData is called with a price that would liquidate the position
     * @custom:given A current price below the position's liquidation price
     * @custom:when _prepareValidateOpenPositionData is called
     * @custom:then The matching data is returned
     * @custom:and The position should have been liquidated
     * @custom:and the function should have returned early
     */
    function test_prepareValidateOpenPositionDataWithALiquidatedPosition() public {
        _waitDelay();
        currentPriceData = abi.encode(liqPriceWithoutPenalty);

        vm.expectEmit();
        emit StalePendingActionRemoved(address(this), posId);
        (ValidateOpenPositionData memory data, bool liquidated) =
            protocol.i_prepareValidateOpenPositionData(pendingAction, currentPriceData);

        // increase tick version as the position was liquidated
        posId.tickVersion++;

        assertTrue(liquidated, "The position should have been liquidated");
        assertFalse(data.isLiquidationPending, "There should be no pending liquidation");
        _assertData(data, true);
    }

    /**
     * @custom:scenario _prepareValidateOpenPositionData is called with 2 ticks that can be liquidated
     * @custom:given A current price below the position's liquidation price
     * @custom:and A high risk position that will be liquidated first
     * @custom:and A liquidation iterations setting at 1
     * @custom:when _prepareValidateOpenPositionData is called
     * @custom:then The matching data is returned
     * @custom:and The provided position was not liquidated
     * @custom:and The function should have returned early
     * @custom:and There should be pending liquidations
     */
    function test_prepareValidateOpenPositionDataWithPendingLiquidations() public {
        // open longs to liquidate
        vm.prank(USER_1);
        protocol.initiateOpenPosition(
            POSITION_AMOUNT,
            params.initialPrice * 9 / 10,
            type(uint128).max,
            protocol.getMaxLeverage(),
            USER_1,
            USER_1,
            type(uint256).max,
            currentPriceData,
            EMPTY_PREVIOUS_DATA
        );

        _waitDelay();

        vm.prank(ADMIN);
        protocol.setLiquidationIteration(1);

        currentPriceData = abi.encode(liqPriceWithoutPenalty);

        (ValidateOpenPositionData memory data, bool liquidated) =
            protocol.i_prepareValidateOpenPositionData(pendingAction, currentPriceData);

        assertFalse(liquidated, "The position should have been liquidated");
        assertTrue(data.isLiquidationPending, "There should be pending liquidations");
        _assertData(data, true);
    }

    /// @notice Assert the data in ValidateOpenPositionData depending on `isEarlyReturn`
    function _assertData(ValidateOpenPositionData memory data, bool isEarlyReturn) private view {
        uint128 currentPrice = abi.decode(currentPriceData, (uint128));
        uint24 liquidationPenalty = protocol.getLiquidationPenalty();
        uint256 positionTotalExpo =
            protocol.i_calcPositionTotalExpo(POSITION_AMOUNT, params.initialPrice, liqPriceWithoutPenalty);

        // asserts that should be done independently from the `isEarlyReturn` param
        assertEq(
            data.tickHash,
            protocol.tickHash(posId.tick, posId.tickVersion),
            "The tick hash should match the provided position's ID"
        );
        assertEq(data.startPrice, currentPrice, "The last price should match the expected value");

        if (isEarlyReturn) {
            Position memory defaultPos;
            assertEq(abi.encode(data.pos), abi.encode(defaultPos), "The position should have default values");
            assertEq(data.liquidationPenalty, 0, "The liquidation penalty should be 0");
            assertEq(data.liqPriceWithoutPenalty, 0, "The liquidation price should be 0");
            assertEq(data.leverage, 0, "The long trading expo should not be set");
        } else {
            assertFalse(data.pos.validated, "The corresponding position should not be validated");
            assertEq(
                data.pos.timestamp,
                timestampAtInitiate,
                "The timestamp should be equal to the timestamp of the initiate action"
            );
            assertEq(
                data.pos.totalExpo, positionTotalExpo, "The total expo of the position should match the expected value"
            );
            assertEq(data.pos.user, address(this), "The user should be this contract");
            assertEq(data.pos.amount, POSITION_AMOUNT, "The amount of the position should match the expected value");

            assertEq(
                data.liquidationPenalty, liquidationPenalty, "The liquidation penalty should match the expected value"
            );
            assertEq(
                data.liqPriceWithoutPenalty,
                liqPriceWithoutPenalty,
                "The liquidation price should match the expected value"
            );
            assertEq(
                data.leverage,
                protocol.i_getLeverage(params.initialPrice, liqPriceWithoutPenalty),
                "The leverage should match the expected value"
            );
        }
    }
}

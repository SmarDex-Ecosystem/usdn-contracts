// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { FixedPointMathLib } from "solady/src/utils/FixedPointMathLib.sol";

import {
    LongPendingAction,
    Position,
    PreviousActionsData,
    ProtocolAction,
    TickData,
    PositionId
} from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";

import { UsdnProtocolBaseFixture } from "test/unit/UsdnProtocol/utils/Fixtures.sol";
import { USER_1 } from "test/utils/Constants.sol";

/**
 * @custom:feature The validate close position functions of the USDN Protocol
 * @custom:background Given a protocol initialized with 10 wstETH in the vault and 5 wstETH in a long position with a
 * leverage of ~2x
 * @custom:and a validated long position of 1 ether with 10x leverage
 */
contract TestUsdnProtocolActionsInitiateClosePosition is UsdnProtocolBaseFixture {
    using SafeCast for uint256;

    uint128 private positionAmount = 1 ether;
    int24 private tick;
    uint256 private tickVersion;
    uint256 private index;

    function setUp() public {
        params = DEFAULT_PARAMS;
        params.flags.enableFunding = false;
        params.flags.enablePositionFees = false;
        params.flags.enableProtocolFees = false;

        super._setUp(params);

        (tick, tickVersion, index) = setUpUserPositionInLong(
            OpenParams({
                user: address(this),
                untilAction: ProtocolAction.ValidateOpenPosition,
                positionSize: positionAmount,
                desiredLiqPrice: params.initialPrice - (params.initialPrice / 5),
                price: params.initialPrice
            })
        );
    }

    /* -------------------------------------------------------------------------- */
    /*                                   Reverts                                  */
    /* -------------------------------------------------------------------------- */

    /**
     * @custom:scenario A user tries to close a position with an amount higher than the position's amount
     * @custom:given A validated open position
     * @custom:when The owner of the position calls initiateClosePosition with an amount too high
     * @custom:then The call reverts
     */
    function test_RevertWhen_closePartialPositionWithAmountHigherThanPositionAmount() external {
        bytes memory priceData = abi.encode(params.initialPrice);
        uint128 amountToClose = positionAmount + 1;

        vm.expectRevert(
            abi.encodeWithSelector(
                UsdnProtocolAmountToCloseHigherThanPositionAmount.selector, amountToClose, positionAmount
            )
        );
        protocol.i_initiateClosePosition(
            address(this),
            address(this),
            PositionId({ tick: tick, tickVersion: tickVersion, index: index }),
            amountToClose,
            priceData
        );
    }

    /**
     * @custom:scenario The sender is not the owner of the position
     * @custom:when The user initiates a close of another user's position
     * @custom:then The protocol reverts with `UsdnProtocolUnauthorized`
     */
    function test_RevertWhen_notUser() public {
        bytes memory priceData = abi.encode(params.initialPrice);
        vm.expectRevert(UsdnProtocolUnauthorized.selector);
        protocol.i_initiateClosePosition(
            USER_1,
            USER_1,
            PositionId({ tick: tick, tickVersion: tickVersion, index: index }),
            positionAmount,
            priceData
        );
    }

    /**
     * @custom:scenario The user initiates a close position with parameter to defined at zero
     * @custom:when The user initiates a close position with parameter to defined at zero
     * @custom:then The protocol reverts with `UsdnProtocolZeroAddressTo`
     */
    function test_RevertWhen_zeroAddressTo() public {
        bytes memory priceData = abi.encode(params.initialPrice);
        vm.expectRevert(UsdnProtocolZeroAddressTo.selector);
        protocol.i_initiateClosePosition(
            USER_1, address(0), PositionId(tick, tickVersion, index), positionAmount, priceData
        );
    }

    /**
     * @custom:scenario A user tries to close a position with 0 as the amount to close
     * @custom:given A validated open position
     * @custom:when The owner of the position calls initiateClosePosition with 0 as the amount to close
     * @custom:then The call reverts
     */
    function test_RevertWhen_closePartialPositionWithZeroAmount() external {
        bytes memory priceData = abi.encode(params.initialPrice);

        vm.expectRevert(abi.encodeWithSelector(UsdnProtocolAmountToCloseIsZero.selector));
        protocol.i_initiateClosePosition(
            address(this),
            address(this),
            PositionId({ tick: tick, tickVersion: tickVersion, index: index }),
            0,
            priceData
        );
    }

    /**
     * @custom:scenario A user tries to close a position that was previously liquidated
     * @custom:given A validated open position gets liquidated
     * @custom:when The owner of the position calls initiateClosePosition with half of the amount
     * @custom:then The call reverts because the position is not valid anymore
     */
    function test_RevertWhen_closePartialPositionWithAnOutdatedTick() external {
        bytes memory priceData = abi.encode(protocol.getEffectivePriceForTick(tick));

        // Liquidate the position
        protocol.liquidate(priceData, 1);
        (, uint256 version) = protocol.i_tickHash(tick);
        assertGt(version, tickVersion, "The tick should have been liquidated");

        // Try to close the position once the price comes back up
        priceData = abi.encode(params.initialPrice);
        vm.expectRevert(abi.encodeWithSelector(UsdnProtocolOutdatedTick.selector, tickVersion + 1, tickVersion));
        protocol.i_initiateClosePosition(
            address(this),
            address(this),
            PositionId({ tick: tick, tickVersion: tickVersion, index: index }),
            positionAmount / 2,
            priceData
        );
    }

    /* -------------------------------------------------------------------------- */
    /*                            initiateClosePosition                           */
    /* -------------------------------------------------------------------------- */

    /**
     * @custom:scenario A user initiates a close position action but sends too much ether
     * @custom:given A validated long position
     * @custom:and oracle validation cost == 0
     * @custom:when User calls initiateClosePosition with an amount of ether greater than the validation cost
     * @custom:then The protocol refunds the amount sent
     */
    function test_initiateClosePositionRefundExcessEther() external {
        bytes memory priceData = abi.encode(params.initialPrice);
        uint256 etherBalanceBefore = address(this).balance;

        protocol.initiateClosePosition{ value: 1 ether }(
            tick, tickVersion, index, positionAmount, priceData, EMPTY_PREVIOUS_DATA, address(this)
        );

        assertEq(
            etherBalanceBefore,
            address(this).balance,
            "The sent ether should have been refunded as none of it was spent"
        );
    }

    /**
     * @custom:scenario A user initiates a close position action with a pending action
     * @custom:given A validated long position
     * @custom:and an initiated open position action from another user
     * @custom:when User calls initiateClosePosition with valid price data for the pending action
     * @custom:then The user validates the pending action
     */
    function test_initiateClosePositionValidatePendingAction() external {
        bytes memory priceData = abi.encode(params.initialPrice);
        // Initiate an open position action for another user
        setUpUserPositionInLong(
            OpenParams({
                user: USER_1,
                untilAction: ProtocolAction.InitiateOpenPosition,
                positionSize: positionAmount,
                desiredLiqPrice: params.initialPrice - (params.initialPrice / 5),
                price: params.initialPrice
            })
        );

        skip(protocol.getValidationDeadline());

        bytes[] memory previousData = new bytes[](1);
        previousData[0] = priceData;
        uint128[] memory rawIndices = new uint128[](1);
        rawIndices[0] = 1;

        vm.expectEmit(true, false, false, false);
        emit ValidatedOpenPosition(USER_1, USER_1, 0, 0, 0, 0, 0);
        protocol.initiateClosePosition(
            tick, tickVersion, index, positionAmount, priceData, PreviousActionsData(previousData, rawIndices), USER_1
        );
    }

    /**
     * @custom:scenario A user initiates a close position action
     * @custom:given A validated long position
     * @custom:when User calls initiateClosePosition
     * @custom:then The user initiates a close position action for his position
     */
    function test_initiateClosePosition() external {
        bytes memory priceData = abi.encode(params.initialPrice);

        vm.expectEmit();
        emit InitiatedClosePosition(address(this), address(this), tick, tickVersion, index, 0, 0);
        protocol.initiateClosePosition(
            tick, tickVersion, index, positionAmount, priceData, EMPTY_PREVIOUS_DATA, address(this)
        );
    }

    /* -------------------------------------------------------------------------- */
    /*                           _initiateClosePosition                           */
    /* -------------------------------------------------------------------------- */

    /**
     * @custom:scenario Initiate close a position fully
     * @custom:given A validated open position
     * @custom:when The owner of the position closes all of the position at the same price as the opening
     * @custom:then The state of the protocol is updated
     * @custom:and an InitiatedClosePosition event is emitted
     * @custom:and the position is deleted
     */
    function test_internalInitiateClosePosition() external {
        _internalInitiateClosePositionScenario(address(this));
    }

    /**
     * @custom:scenario Initiate close a position fully
     * @custom:given A validated open position
     * @custom:when The owner of the position closes all of the position at the same price as the opening
     * @custom:and the to parameter is different from the sender
     * @custom:then The state of the protocol is updated
     * @custom:and an InitiatedClosePosition event is emitted
     * @custom:and the position is deleted
     */
    function test_internalInitiateClosePositionForAnotherUser() external {
        _internalInitiateClosePositionScenario(USER_1);
    }

    function _internalInitiateClosePositionScenario(address to) internal {
        uint256 totalLongPositionBefore = protocol.getTotalLongPositions();
        TickData memory tickData = protocol.getTickData(tick);
        _initiateCloseAPositionHelper(positionAmount, to);

        /* ---------------------------- Position's state ---------------------------- */
        (Position memory posAfter,) = protocol.getLongPosition(tick, tickVersion, index);
        assertEq(posAfter.user, address(0), "The user of the position should have been reset");
        assertEq(posAfter.timestamp, 0, "Timestamp of the position should have been reset");
        assertEq(posAfter.totalExpo, 0, "The total expo of the position should be 0");
        assertEq(posAfter.amount, 0, "The amount of the position should be 0");

        /* ---------------------------- Protocol's State ---------------------------- */
        TickData memory newTickData = protocol.getTickData(tick);
        assertEq(
            totalLongPositionBefore - 1,
            protocol.getTotalLongPositions(),
            "The amount of long positions should have decreased by one"
        );
        assertEq(
            tickData.totalPos - 1,
            newTickData.totalPos,
            "The amount of long positions on the tick should have decreased by one"
        );
    }

    /**
     * @custom:scenario Initiate close a position partially
     * @custom:given A validated open position
     * @custom:when The owner of the position closes half of the position at the same price as the opening
     * @custom:then The state of the protocol is updated
     * @custom:and an InitiatedClosePosition event is emitted
     * @custom:and the position still exists
     */
    function test_internalInitiateClosePositionPartially() external {
        uint128 amountToClose = positionAmount / 2;
        uint256 totalLongPositionBefore = protocol.getTotalLongPositions();
        TickData memory tickData = protocol.getTickData(tick);
        (Position memory posBefore,) = protocol.getLongPosition(tick, tickVersion, index);
        uint128 totalExpoToClose =
            FixedPointMathLib.fullMulDiv(posBefore.totalExpo, amountToClose, posBefore.amount).toUint128();
        _initiateCloseAPositionHelper(amountToClose, address(this));

        /* ---------------------------- Position's state ---------------------------- */
        (Position memory posAfter,) = protocol.getLongPosition(tick, tickVersion, index);
        assertEq(posBefore.user, posAfter.user, "The user of the position should not have changed");
        assertEq(posBefore.timestamp, posAfter.timestamp, "Timestamp of the position should have stayed the same");
        assertEq(
            posBefore.totalExpo - totalExpoToClose,
            posAfter.totalExpo,
            "The total expo to close should have been subtracted from the original total expo of the position"
        );
        assertEq(
            posBefore.amount - amountToClose,
            posAfter.amount,
            "The amount to close should have been subtracted from the original amount of the position"
        );

        /* ---------------------------- Protocol's State ---------------------------- */
        TickData memory newTickData = protocol.getTickData(tick);
        assertEq(
            totalLongPositionBefore,
            protocol.getTotalLongPositions(),
            "The amount of long positions should not have changed"
        );
        assertEq(
            tickData.totalPos, newTickData.totalPos, "The amount of long positions on the tick should not have changed"
        );
    }

    /**
     * @notice Helper function to avoid duplicating code between the partial and full close position tests
     * @param amountToClose Amount of the position to close
     */
    function _initiateCloseAPositionHelper(uint128 amountToClose, address to) internal {
        uint256 liquidationMultiplier = protocol.getLiquidationMultiplier();

        (Position memory posBefore,) = protocol.getLongPosition(tick, tickVersion, index);
        uint128 totalExpoToClose =
            FixedPointMathLib.fullMulDiv(posBefore.totalExpo, amountToClose, posBefore.amount).toUint128();
        (uint256 assetToTransfer,) = protocol.i_assetToTransfer(
            params.initialPrice, tick, protocol.getLiquidationPenalty(), totalExpoToClose, liquidationMultiplier, 0
        );

        uint256 totalExpoBefore = protocol.getTotalExpo();
        TickData memory tickData = protocol.getTickData(tick);
        uint256 balanceLongBefore = protocol.getBalanceLong();

        /* ------------------------ Initiate the close action ----------------------- */
        vm.expectEmit();
        emit InitiatedClosePosition(
            address(this),
            to,
            tick,
            tickVersion,
            index,
            posBefore.amount - amountToClose,
            posBefore.totalExpo - totalExpoToClose
        );
        protocol.i_initiateClosePosition(
            address(this),
            to,
            PositionId({ tick: tick, tickVersion: tickVersion, index: index }),
            amountToClose,
            abi.encode(params.initialPrice)
        );

        /* ------------------------- Pending action's state ------------------------- */
        LongPendingAction memory action = protocol.i_toLongPendingAction(protocol.getUserPendingAction(address(this)));
        assertTrue(action.action == ProtocolAction.ValidateClosePosition, "The action type is wrong");
        assertEq(action.timestamp, block.timestamp, "The block timestamp should be now");
        assertEq(action.user, address(this), "The user should be the transaction sender");
        assertEq(action.to, to, "To is wrong");
        assertEq(action.tick, tick, "The position tick is wrong");
        assertEq(
            action.closeTotalExpo, totalExpoToClose, "Total expo of pending action should be equal to totalExpoToClose"
        );
        assertEq(
            action.closeAmount, amountToClose, "Amount of the pending action should be equal to the amount to close"
        );
        assertEq(action.tickVersion, tickVersion, "The tick version should not have changed");
        assertEq(action.index, index, "The index should not have changed");
        assertEq(action.closeLiqMultiplier, liquidationMultiplier, "The liquidation multiplier should not have changed");
        assertEq(action.closeTempTransfer, assetToTransfer, "The close temp transfer should not have changed");

        /* ----------------------------- Protocol State ----------------------------- */
        TickData memory newTickData = protocol.getTickData(tick);
        assertEq(
            totalExpoBefore - totalExpoToClose,
            protocol.getTotalExpo(),
            "totalExpoToClose should have been subtracted from the total expo of the protocol"
        );
        assertEq(
            tickData.totalExpo - totalExpoToClose,
            newTickData.totalExpo,
            "totalExpoToClose should have been subtracted to the total expo on the tick"
        );
        assertEq(
            balanceLongBefore - assetToTransfer,
            protocol.getBalanceLong(),
            "assetToTransfer should have been subtracted from the long balance of the protocol"
        );
    }

    /// @dev Allow refund tests
    receive() external payable { }
}

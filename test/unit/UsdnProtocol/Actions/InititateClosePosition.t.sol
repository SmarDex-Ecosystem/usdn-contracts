// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { FixedPointMathLib } from "solady/src/utils/FixedPointMathLib.sol";

import { UsdnProtocolBaseFixture } from "test/unit/UsdnProtocol/utils/Fixtures.sol";
import { ADMIN, USER_1 } from "test/utils/Constants.sol";

import {
    LongPendingAction,
    PendingAction,
    Position,
    PreviousActionsData,
    ProtocolAction,
    TickData,
    PositionId
} from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import { InitializableReentrancyGuard } from "src/utils/InitializableReentrancyGuard.sol";

/**
 * @custom:feature The validate close position functions of the USDN Protocol
 * @custom:background Given a protocol initialized with 10 wstETH in the vault and 5 wstETH in a long position with a
 * leverage of ~2x
 * @custom:and a validated long position of 1 ether with 10x leverage
 */
contract TestUsdnProtocolActionsInitiateClosePosition is UsdnProtocolBaseFixture {
    using SafeCast for uint256;

    uint128 private constant POSITION_AMOUNT = 1 ether;
    uint256 internal securityDeposit;
    PositionId private posId;
    /// @notice Trigger a reentrancy after receiving ether
    bool internal _reenter;

    function setUp() public {
        super._setUp(DEFAULT_PARAMS);

        posId = setUpUserPositionInLong(
            OpenParams({
                user: address(this),
                untilAction: ProtocolAction.ValidateOpenPosition,
                positionSize: POSITION_AMOUNT,
                desiredLiqPrice: params.initialPrice - (params.initialPrice / 5),
                price: params.initialPrice
            })
        );

        securityDeposit = protocol.getSecurityDepositValue();
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
        uint128 amountToClose = POSITION_AMOUNT + 1;

        vm.expectRevert(
            abi.encodeWithSelector(
                UsdnProtocolAmountToCloseHigherThanPositionAmount.selector, amountToClose, POSITION_AMOUNT
            )
        );
        protocol.i_initiateClosePosition(
            address(this), address(this), posId, amountToClose, address(protocol).balance, priceData
        );
    }

    /**
     * @custom:scenario A user tries to close a position with a remaining amount lower than the min long position
     * @custom:given A validated open position
     * @custom:when The owner of the position calls initiateClosePosition with
     * an amount higher than POSITION_AMOUNT - minLongPosition
     * @custom:then The call reverts with the UsdnProtocolLongPositionTooSmall error
     */
    function test_RevertWhen_closePartialPositionWithAmountRemainingLowerThanMinLongPosition() external {
        vm.prank(ADMIN);
        protocol.setMinLongPosition(POSITION_AMOUNT / 2);

        bytes memory priceData = abi.encode(params.initialPrice);
        uint128 amountToClose = POSITION_AMOUNT / 2 + 1;

        // Sanity check
        assertLt(
            POSITION_AMOUNT - amountToClose,
            POSITION_AMOUNT / 2,
            "The amount remaining is too high to trigger the error"
        );

        vm.expectRevert(UsdnProtocolLongPositionTooSmall.selector);
        protocol.i_initiateClosePosition(
            address(this), address(this), posId, amountToClose, address(protocol).balance, priceData
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
        protocol.i_initiateClosePosition(USER_1, USER_1, posId, POSITION_AMOUNT, address(protocol).balance, priceData);
    }

    /**
     * @custom:scenario The user initiates a close position with parameter to defined at zero
     * @custom:given An initialized USDN protocol
     * @custom:when The user initiates a close position with parameter to defined at zero
     * @custom:then The protocol reverts with `UsdnProtocolInvalidAddressTo`
     */
    function test_RevertWhen_zeroAddressTo() public {
        bytes memory priceData = abi.encode(params.initialPrice);
        vm.expectRevert(UsdnProtocolInvalidAddressTo.selector);
        protocol.i_initiateClosePosition(
            address(this), address(0), posId, POSITION_AMOUNT, address(protocol).balance, priceData
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
        protocol.i_initiateClosePosition(address(this), address(this), posId, 0, address(protocol).balance, priceData);
    }

    /**
     * @custom:scenario A user tries to close a position that was previously liquidated
     * @custom:given A validated open position gets liquidated
     * @custom:when The owner of the position calls initiateClosePosition with half of the amount
     * @custom:then The call reverts because the position is not valid anymore
     */
    function test_RevertWhen_closePartialPositionWithAnOutdatedTick() external {
        _waitBeforeLiquidation();
        bytes memory priceData = abi.encode(protocol.getEffectivePriceForTick(posId.tick));

        // we need wait delay to make the new price data fresh
        _waitDelay();
        // Liquidate the position
        protocol.testLiquidate(priceData, 1);
        (, uint256 version) = protocol.i_tickHash(posId.tick);
        assertGt(version, posId.tickVersion, "The tick should have been liquidated");

        // Try to close the position once the price comes back up
        priceData = abi.encode(params.initialPrice);
        vm.expectRevert(
            abi.encodeWithSelector(UsdnProtocolOutdatedTick.selector, posId.tickVersion + 1, posId.tickVersion)
        );
        protocol.i_initiateClosePosition(
            address(this), address(this), posId, POSITION_AMOUNT / 2, address(protocol).balance, priceData
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
            posId, POSITION_AMOUNT, priceData, EMPTY_PREVIOUS_DATA, address(this)
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
                positionSize: POSITION_AMOUNT,
                desiredLiqPrice: params.initialPrice - (params.initialPrice / 5),
                price: params.initialPrice
            })
        );

        skip(protocol.getValidationDeadline());

        bytes[] memory previousData = new bytes[](1);
        previousData[0] = priceData;
        uint128[] memory rawIndices = new uint128[](1);
        rawIndices[0] = 1;

        vm.expectEmit(true, true, false, false);
        emit ValidatedOpenPosition(USER_1, USER_1, 0, 0, PositionId(0, 0, 0));
        protocol.initiateClosePosition(
            posId, POSITION_AMOUNT, priceData, PreviousActionsData(previousData, rawIndices), USER_1
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
        emit InitiatedClosePosition(address(this), address(this), posId, POSITION_AMOUNT, POSITION_AMOUNT, 0);
        protocol.initiateClosePosition(posId, POSITION_AMOUNT, priceData, EMPTY_PREVIOUS_DATA, address(this));
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
        TickData memory tickData = protocol.getTickData(posId.tick);
        _initiateCloseAPositionHelper(POSITION_AMOUNT, to);

        /* ---------------------------- Position's state ---------------------------- */
        (Position memory posAfter,) = protocol.getLongPosition(posId);
        assertEq(posAfter.user, address(0), "The user of the position should have been reset");
        assertEq(posAfter.timestamp, 0, "Timestamp of the position should have been reset");
        assertEq(posAfter.totalExpo, 0, "The total expo of the position should be 0");
        assertEq(posAfter.amount, 0, "The amount of the position should be 0");

        /* ---------------------------- Protocol's State ---------------------------- */
        TickData memory newTickData = protocol.getTickData(posId.tick);
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
        uint128 amountToClose = POSITION_AMOUNT / 2;
        uint256 totalLongPositionBefore = protocol.getTotalLongPositions();
        TickData memory tickData = protocol.getTickData(posId.tick);
        (Position memory posBefore,) = protocol.getLongPosition(posId);
        uint128 totalExpoToClose =
            FixedPointMathLib.fullMulDiv(posBefore.totalExpo, amountToClose, posBefore.amount).toUint128();
        _initiateCloseAPositionHelper(amountToClose, address(this));

        /* ---------------------------- Position's state ---------------------------- */
        (Position memory posAfter,) = protocol.getLongPosition(posId);
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
        TickData memory newTickData = protocol.getTickData(posId.tick);
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
     * @custom:scenario A initiate close liquidates a pending tick but is not validated
     * because a tick still need to be liquidated
     * @custom:given The initial open position
     * @custom:and A first user open position
     * @custom:and A second user open position with a liquidation price below all others
     * @custom:and The price drop below the initiate and the first user open position
     * @custom:when The first `initiateClosePosition` is called
     * @custom:and The initial open position tick is liquidated
     * @custom:and The first user open position tick still need to be liquidated
     * @custom:and The user close isn't validated
     * @custom:then The transaction is completed
     * @custom:when The second `initiateClosePosition` is called
     * @custom:and The first user open position tick is liquidated
     * @custom:and No more tick needs to be liquidated
     * @custom:and The user close is validated
     * @custom:then The transaction is completed
     */
    function test_initiateClosePositionIsPendingLiquidation() public {
        // initial open position
        (int24 initialPosTick, uint256 initialPosTickVersion) = _getInitialLongPosition();

        // open position with a liquidation price far lower than others positions
        PositionId memory userPosId = setUpUserPositionInLong(
            OpenParams(
                address(this),
                ProtocolAction.ValidateOpenPosition,
                POSITION_AMOUNT,
                params.initialPrice / 30,
                params.initialPrice
            )
        );

        _waitMockMiddlewarePriceDelay();

        {
            protocol.initiateClosePosition{ value: securityDeposit }(
                userPosId, POSITION_AMOUNT, abi.encode(params.initialPrice / 10), EMPTY_PREVIOUS_DATA, address(this)
            );

            PendingAction memory pending = protocol.getUserPendingAction(address(this));
            assertEq(uint256(pending.action), uint256(ProtocolAction.None), "action is initiated");

            assertEq(
                posId.tickVersion + 1, protocol.getTickVersion(posId.tick), "first user position is not liquidated"
            );

            assertEq(initialPosTickVersion, protocol.getTickVersion(initialPosTick), "initial position is liquidated");
        }

        _waitMockMiddlewarePriceDelay();

        {
            protocol.initiateClosePosition{ value: securityDeposit }(
                userPosId, POSITION_AMOUNT, abi.encode(params.initialPrice / 10), EMPTY_PREVIOUS_DATA, address(this)
            );

            PendingAction memory pending = protocol.getUserPendingAction(address(this));
            assertEq(uint256(pending.action), uint256(ProtocolAction.ValidateClosePosition), "action is not initiated");

            assertEq(
                initialPosTickVersion + 1, protocol.getTickVersion(initialPosTick), "initial position isn't liquidated"
            );
        }
    }

    /**
     * @custom:scenario A initiate close liquidates a tick but is not validated
     * because a tick still need to be liquidated. In the same block another close
     * liquid the remaining tick and is validated
     * @custom:given The initial open position
     * @custom:and A first user open position
     * @custom:and A second user open position with a liquidation price below all others
     * @custom:and The price drop below the initiate and the first user open position
     * @custom:when The first `initiateClosePosition` is called
     * @custom:and The initial open position tick is liquidated
     * @custom:and The first user open position tick still need to be liquidated
     * @custom:and The user close isn't validated
     * @custom:then The transaction is completed
     * @custom:when The second `initiateClosePosition` is called in the same block
     * @custom:and The first user open position tick is liquidated
     * @custom:and No more tick needs to be liquidated
     * @custom:and The user close is validated
     * @custom:then The transaction is completed
     */
    function test_initiateClosePositionSameBlockIsPendingLiquidation() public {
        // initial open position
        (int24 initialPosTick, uint256 initialPosTickVersion) = _getInitialLongPosition();

        // open position with a liquidation price far lower than others positions
        PositionId memory userPosId = setUpUserPositionInLong(
            OpenParams(
                address(this),
                ProtocolAction.ValidateOpenPosition,
                POSITION_AMOUNT,
                params.initialPrice / 30,
                params.initialPrice
            )
        );

        _waitMockMiddlewarePriceDelay();

        {
            protocol.initiateClosePosition{ value: securityDeposit }(
                userPosId, POSITION_AMOUNT, abi.encode(params.initialPrice / 10), EMPTY_PREVIOUS_DATA, address(this)
            );

            PendingAction memory pending = protocol.getUserPendingAction(address(this));
            assertEq(uint256(pending.action), uint256(ProtocolAction.None), "action is initiated");

            assertEq(
                posId.tickVersion + 1, protocol.getTickVersion(posId.tick), "first user position is not liquidated"
            );

            assertEq(initialPosTickVersion, protocol.getTickVersion(initialPosTick), "initial position is liquidated");
        }

        {
            protocol.initiateClosePosition{ value: securityDeposit }(
                userPosId, POSITION_AMOUNT, abi.encode(params.initialPrice / 10), EMPTY_PREVIOUS_DATA, address(this)
            );

            PendingAction memory pending = protocol.getUserPendingAction(address(this));
            assertEq(uint256(pending.action), uint256(ProtocolAction.ValidateClosePosition), "action is not initiated");

            assertEq(
                initialPosTickVersion + 1, protocol.getTickVersion(initialPosTick), "initial position isn't liquidated"
            );
        }
    }

    /**
     * @notice Helper function to avoid duplicating code between the partial and full close position tests
     * @param amountToClose Amount of the position to close
     */
    function _initiateCloseAPositionHelper(uint128 amountToClose, address to) internal {
        (Position memory posBefore,) = protocol.getLongPosition(posId);
        uint128 totalExpoToClose =
            FixedPointMathLib.fullMulDiv(posBefore.totalExpo, amountToClose, posBefore.amount).toUint128();
        uint256 totalExpoBefore = protocol.getTotalExpo();
        uint256 balanceLongBefore = protocol.getBalanceLong();
        uint256 assetToTransfer = protocol.i_assetToRemove(
            params.initialPrice,
            protocol.getEffectivePriceForTick(
                protocol.i_calcTickWithoutPenalty(posId.tick),
                params.initialPrice,
                totalExpoBefore - balanceLongBefore,
                protocol.getLiqMultiplierAccumulator()
            ),
            totalExpoToClose
        );

        TickData memory tickData = protocol.getTickData(posId.tick);

        /* ------------------------ Initiate the close action ----------------------- */
        vm.expectEmit();
        emit InitiatedClosePosition(
            address(this), to, posId, posBefore.amount, amountToClose, posBefore.totalExpo - totalExpoToClose
        );
        protocol.i_initiateClosePosition(
            address(this), to, posId, amountToClose, address(protocol).balance, abi.encode(params.initialPrice)
        );

        /* ------------------------- Pending action's state ------------------------- */
        LongPendingAction memory action = protocol.i_toLongPendingAction(protocol.getUserPendingAction(address(this)));
        assertTrue(action.action == ProtocolAction.ValidateClosePosition, "The action type is wrong");
        assertEq(action.timestamp, block.timestamp, "The block timestamp should be now");
        assertEq(action.user, address(this), "The user should be the transaction sender");
        assertEq(action.to, to, "To is wrong");
        assertEq(action.tick, posId.tick, "The position tick is wrong");
        assertEq(
            action.closePosTotalExpo,
            totalExpoToClose,
            "Total expo of pending action should be equal to totalExpoToClose"
        );
        assertEq(
            action.closeAmount, amountToClose, "Amount of the pending action should be equal to the amount to close"
        );
        assertEq(action.tickVersion, posId.tickVersion, "The tick version should not have changed");
        assertEq(action.index, posId.index, "The index should not have changed");
        assertEq(action.closeBoundedPositionValue, assetToTransfer, "The pos value should not have changed");

        /* ----------------------------- Protocol State ----------------------------- */
        TickData memory newTickData = protocol.getTickData(posId.tick);
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

    /**
     * @custom:scenario The user initiates a close position action with a reentrancy attempt
     * @custom:given A user being a smart contract that calls initiateClosePosition with too much ether
     * @custom:and A receive() function that calls initiateClosePosition again
     * @custom:when The user calls initiateClosePosition again from the callback
     * @custom:then The call reverts with InitializableReentrancyGuardReentrantCall
     */
    function test_RevertWhen_initiateClosePositionCalledWithReentrancy() public {
        // If we are currently in a reentrancy
        if (_reenter) {
            vm.expectRevert(InitializableReentrancyGuard.InitializableReentrancyGuardReentrantCall.selector);
            protocol.initiateClosePosition(
                posId, POSITION_AMOUNT, abi.encode(params.initialPrice), EMPTY_PREVIOUS_DATA, address(this)
            );
            return;
        }

        setUpUserPositionInLong(
            OpenParams({
                user: address(this),
                untilAction: ProtocolAction.ValidateOpenPosition,
                positionSize: POSITION_AMOUNT,
                desiredLiqPrice: params.initialPrice - (params.initialPrice / 5),
                price: params.initialPrice
            })
        );

        _reenter = true;
        // If a reentrancy occurred, the function should have been called 2 times
        vm.expectCall(address(protocol), abi.encodeWithSelector(protocol.initiateClosePosition.selector), 2);
        // The value sent will cause a refund, which will trigger the receive() function of this contract
        protocol.initiateClosePosition{ value: 1 }(
            posId, POSITION_AMOUNT, abi.encode(params.initialPrice), EMPTY_PREVIOUS_DATA, address(this)
        );
    }

    /// @dev Allow refund tests
    receive() external payable {
        // test reentrancy
        if (_reenter) {
            test_RevertWhen_initiateClosePositionCalledWithReentrancy();
            _reenter = false;
        }
    }
}

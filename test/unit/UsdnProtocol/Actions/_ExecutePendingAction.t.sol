// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { USER_1 } from "test/utils/Constants.sol";
import { UsdnProtocolBaseFixture } from "test/unit/UsdnProtocol/utils/Fixtures.sol";

import {
    PendingAction,
    ProtocolAction,
    PreviousActionsData,
    PositionId
} from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";

/**
 * @custom:feature Test the _executePendingAction internal function of the actions layer
 * @custom:given A protocol with all fees, rebase and funding disabled
 */
contract TestUsdnProtocolActionsExecutePendingAction is UsdnProtocolBaseFixture {
    function setUp() public {
        _setUp(DEFAULT_PARAMS);
    }

    /**
     * @custom:scenario Execute a pending action
     * @custom:given A pending action in the queue
     * @custom:when The `_executePendingAction` internal function is called with the correct calldata
     * @custom:then The action is executed and the pending action is removed from the queue
     */
    function test_executePendingAction() public {
        PreviousActionsData memory previousActionsData = _setUpPendingAction();

        vm.expectEmit(true, true, false, false);
        emit ValidatedOpenPosition(USER_1, USER_1, 0, 0, PositionId(0, 0, 0));
        (bool success, bool executed,) = protocol.i_executePendingAction(previousActionsData);

        assertTrue(success, "success");
        assertTrue(executed, "executed");

        (PendingAction[] memory actions,) = protocol.getActionablePendingActions(address(this));
        assertEq(actions.length, 0, "remaining pending actions");

        PendingAction memory action = protocol.getUserPendingAction(USER_1);
        assertTrue(action.action == ProtocolAction.None, "no user pending action");
    }

    /**
     * @custom:scenario Execute a pending action when there is none
     * @custom:given No pending actions in the queue
     * @custom:when The `_executePendingAction` internal function is called
     * @custom:then The function returns true for `success` and false for `executed`
     */
    function test_executePendingActionNone() public {
        (bool success, bool executed,) = protocol.i_executePendingAction(EMPTY_PREVIOUS_DATA);
        assertTrue(success, "success");
        assertEq(executed, false, "executed");
    }

    /**
     * @custom:scenario Execute a pending action when the length of price data and raw indices do not match
     * @custom:given A pending action in the queue
     * @custom:when The `_executePendingAction` internal function is called with a `PreviousActionsData` with different
     * lengths of price data and raw indices
     * @custom:then The function returns false for `success` and `executed`
     */
    function test_executePendingActionLengthMismatch() public {
        PreviousActionsData memory previousActionsData = _setUpPendingAction();
        previousActionsData.rawIndices = new uint128[](0);

        (bool success, bool executed,) = protocol.i_executePendingAction(previousActionsData);
        assertEq(success, false, "success");
        assertEq(executed, false, "executed");
    }

    /**
     * @custom:scenario Execute a pending action when the price data and raw indices are empty
     * @custom:given A pending action in the queue
     * @custom:when The `_executePendingAction` internal function is called with an empty `PreviousActionsData`
     * @custom:then The function returns false for `success` and `executed`
     */
    function test_executePendingActionEmptyData() public {
        _setUpPendingAction();
        (bool success, bool executed,) = protocol.i_executePendingAction(EMPTY_PREVIOUS_DATA);
        assertEq(success, false, "success");
        assertEq(executed, false, "executed");
    }

    /**
     * @custom:scenario Execute a pending action when the raw index is not found
     * @custom:given A pending action in the queue
     * @custom:when The `_executePendingAction` internal function is called with a `PreviousActionsData` with a bad raw
     * index
     * @custom:then The function returns false for `success` and `executed`
     */
    function test_executePendingActionBadData() public {
        PreviousActionsData memory previousActionsData = _setUpPendingAction();
        previousActionsData.rawIndices[0] = 69;

        (bool success, bool executed,) = protocol.i_executePendingAction(previousActionsData);
        assertEq(success, false, "success");
        assertEq(executed, false, "executed");
    }

    /**
     * @dev Set up a pending action and return the previous actions data
     * @return previousActionsData_ The previous actions data, with the same price as the initial price
     */
    function _setUpPendingAction() internal returns (PreviousActionsData memory previousActionsData_) {
        setUpUserPositionInLong(
            OpenParams({
                user: USER_1,
                untilAction: ProtocolAction.InitiateOpenPosition,
                positionSize: 1 ether,
                desiredLiqPrice: params.initialPrice / 2,
                price: params.initialPrice
            })
        );
        // make actionable
        skip(protocol.getValidationDeadline() + 1);

        (PendingAction[] memory actions, uint128[] memory rawIndices) =
            protocol.getActionablePendingActions(address(this));

        assertEq(actions.length, 1, "actions length");

        bytes[] memory priceData = new bytes[](1);
        priceData[0] = abi.encode(params.initialPrice);
        previousActionsData_ = PreviousActionsData({ priceData: priceData, rawIndices: rawIndices });
    }
}

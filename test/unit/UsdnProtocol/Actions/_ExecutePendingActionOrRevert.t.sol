// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { USER_1 } from "test/utils/Constants.sol";
import { UsdnProtocolBaseFixture } from "test/unit/UsdnProtocol/utils/Fixtures.sol";

import { PendingAction, ProtocolAction, PreviousActionsData } from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";

/**
 * @custom:feature Test the _executePendingActionOrRevert internal function of the actions layer
 * @custom:given A protocol with all fees, rebase and funding disabled
 */
contract TestUsdnProtocolActionsExecutePendingActionOrRevert is UsdnProtocolBaseFixture {
    function setUp() public {
        _setUp(DEFAULT_PARAMS);
    }

    /**
     * @custom:scenario Revert when executing a pending action with different lengths of price data and raw indices
     * @custom:given A pending action in the queue
     * @custom:when A `PreviousActionsData` with different lengths of price data and raw indices
     * @custom:then The execution reverts with `UsdnProtocolInvalidPendingActionData`
     */
    function test_RevertWhen_executePendingActionDifferentLengths() public {
        _addDummyPendingAction();

        // construct bad previous actions data
        PreviousActionsData memory data =
            PreviousActionsData({ priceData: new bytes[](2), rawIndices: new uint128[](1) });

        vm.expectRevert(UsdnProtocolInvalidPendingActionData.selector);
        protocol.i_executePendingActionOrRevert(data);
    }

    /**
     * @custom:scenario Revert when executing a pending action with empty price data and raw indices
     * @custom:given A pending action in the queue
     * @custom:when A `PreviousActionsData` with empty price data and raw indices
     * @custom:then The execution reverts with `UsdnProtocolInvalidPendingActionData`
     */
    function test_RevertWhen_executePendingActionEmpty() public {
        _addDummyPendingAction();

        // construct bad previous actions data
        bytes[] memory priceData = new bytes[](0);
        uint128[] memory rawIndices = new uint128[](0);
        PreviousActionsData memory data = PreviousActionsData({ priceData: priceData, rawIndices: rawIndices });

        vm.expectRevert(UsdnProtocolInvalidPendingActionData.selector);
        protocol.i_executePendingActionOrRevert(data);
    }

    /**
     * @custom:scenario Revert when executing a pending action with bad ordering of raw indices
     * @custom:given A pending action in the queue
     * @custom:when A `PreviousActionsData` with bad ordering of raw indices (the pending action raw index is second
     * and smaller than the first item in the array)
     * @custom:then The execution reverts with `UsdnProtocolInvalidPendingActionData`
     */
    function test_RevertWhen_executePendingActionBadOrdering() public {
        uint128 rawIndex = _addDummyPendingAction();

        // construct bad previous actions data
        bytes[] memory priceData = new bytes[](2);
        uint128[] memory rawIndices = new uint128[](2);
        rawIndices[0] = rawIndex + 1;
        rawIndices[1] = rawIndex;
        PreviousActionsData memory data = PreviousActionsData({ priceData: priceData, rawIndices: rawIndices });

        vm.expectRevert(UsdnProtocolInvalidPendingActionData.selector);
        protocol.i_executePendingActionOrRevert(data);
    }

    /**
     * @custom:scenario Executing a pending action with a wrap-around of the raw index
     * @custom:given Two pending actions in queue, with raw indices uint256.max (USER_1) and 0 (this contract)
     * @custom:when The second pending action is executed (uint256.max)
     * @custom:then The execution does not revert and the first pending action is processed
     * @custom:and The remaining pending action is the one for this contract (rawIndex 0)
     */
    function test_executePendingActionWrapAround() public {
        uint128 rawIndex2 = _addDummyPendingAction();
        assertEq(rawIndex2, 0, "raw index 2");

        PendingAction memory pending;
        pending.common.action = ProtocolAction.InitiateDeposit;
        pending.common.validator = USER_1;
        pending.common.timestamp = uint40(block.timestamp - protocol.getValidationDeadline() - 1);
        uint128 rawIndex1 = protocol.queuePushFront(pending);
        assertEq(rawIndex1, type(uint128).max, "raw index 1");

        bytes[] memory priceData = new bytes[](2);
        uint128[] memory rawIndices = new uint128[](2);
        rawIndices[0] = rawIndex1;
        rawIndices[1] = rawIndex2;
        PreviousActionsData memory data = PreviousActionsData({ priceData: priceData, rawIndices: rawIndices });

        protocol.i_executePendingActionOrRevert(data); // should validate `pending` for USER_1

        (PendingAction[] memory actions,) = protocol.getActionablePendingActions(address(0));
        assertEq(actions.length, 1, "one pending action left");
        assertEq(actions[0].common.validator, address(this), "pending action user");
    }

    /**
     * @dev Add a dummy pending action to the queue with this contract as the user.
     * @return rawIndex_ The raw index of the added pending action.
     */
    function _addDummyPendingAction() internal returns (uint128 rawIndex_) {
        PendingAction memory pending;
        pending.common.action = ProtocolAction.InitiateDeposit;
        pending.common.validator = address(this);
        pending.common.timestamp = uint40(block.timestamp - protocol.getValidationDeadline() - 1);
        protocol.i_addPendingAction(address(this), pending);
        (, rawIndex_) = protocol.i_getPendingAction(address(this));
    }
}

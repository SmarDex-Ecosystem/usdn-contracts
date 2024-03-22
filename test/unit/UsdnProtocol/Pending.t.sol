// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { UsdnProtocolBaseFixture } from "test/unit/UsdnProtocol/utils/Fixtures.sol";
import { USER_1, USER_2, USER_3, USER_4 } from "test/utils/Constants.sol";

import {
    PendingAction,
    VaultPendingAction,
    LongPendingAction,
    ProtocolAction,
    PreviousActionsData
} from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";

/**
 * @custom:feature The functions handling the pending actions queue
 * @custom:background Given a protocol instance that was initialized with default params
 */
contract TestUsdnProtocolPending is UsdnProtocolBaseFixture {
    function setUp() public {
        params = DEFAULT_PARAMS;
        params.enablePositionFees = false;
        params.enableProtocolFees = false;
        params.enableFunding = false;
        super._setUp(params);
    }

    /**
     * @custom:scenario Get the actionable pending actions
     * @custom:given The user has initiated a deposit
     * @custom:and The validation deadline has elapsed
     * @custom:when The actionable pending actions are requested
     * @custom:then The pending actions are returned
     */
    function test_getActionablePendingActions() public {
        // there should be no pending action at this stage
        (PendingAction[] memory actions, uint128[] memory rawIndices) = protocol.getActionablePendingActions(address(0));
        assertEq(actions.length, 0, "pending action before initiate");
        // initiate deposit
        setUpUserPositionInVault(address(this), ProtocolAction.InitiateDeposit, 3 ether, 2000 ether);
        // the pending action is not yet actionable
        (actions, rawIndices) = protocol.getActionablePendingActions(address(0));
        assertEq(actions.length, 0, "pending action after initiate");
        // the pending action is actionable after the validation deadline
        skip(protocol.getValidationDeadline() + 1);
        (actions, rawIndices) = protocol.getActionablePendingActions(address(0));
        assertEq(actions.length, 1, "actions length");
        assertEq(actions[0].user, address(this), "action user");
        assertEq(rawIndices[0], 0, "raw index");
    }

    /**
     * @custom:scenario Get the first actionable pending action
     * @custom:given The user has initiated a deposit
     * @custom:and The validation deadline has elapsed
     * @custom:when The first actionable pending action is requested
     * @custom:then The pending action is returned
     */
    function test_internalGetActionablePendingAction() public {
        // there should be no pending action at this stage
        (PendingAction memory action, uint128 rawIndex) = protocol.i_getActionablePendingAction();
        assertTrue(action.action == ProtocolAction.None, "pending action before initiate");
        // initiate long
        setUpUserPositionInVault(address(this), ProtocolAction.InitiateDeposit, 3 ether, 2000 ether);
        // the pending action is not yet actionable
        (action, rawIndex) = protocol.i_getActionablePendingAction();
        assertTrue(action.action == ProtocolAction.None, "pending action after initiate");
        // the pending action is actionable after the validation deadline
        skip(protocol.getValidationDeadline() + 1);
        (action, rawIndex) = protocol.i_getActionablePendingAction();
        assertEq(action.user, address(this), "action user");
        assertEq(rawIndex, 0, "raw index");
    }

    /**
     * @dev Set up 3 user positions in long and artificially remove the pending actions for user 2 and 1, leaving the
     * first item in the queue being zero-valued.
     */
    function _setupSparsePendingActionsQueue() internal {
        // Setup 3 pending actions
        setUpUserPositionInLong(USER_1, ProtocolAction.InitiateOpenPosition, 3 ether, 1000 ether, 2000 ether);
        setUpUserPositionInLong(USER_2, ProtocolAction.InitiateOpenPosition, 3 ether, 1000 ether, 2000 ether);
        setUpUserPositionInLong(USER_3, ProtocolAction.InitiateOpenPosition, 3 ether, 1000 ether, 2000 ether);

        // Simulate the second item in the queue being empty (sets it to zero values)
        protocol.i_removePendingAction(1, USER_2);
        // Simulate the first item in the queue being empty
        // This will pop the first item, but leave the second empty
        protocol.i_removePendingAction(0, USER_1);
    }

    /**
     * @custom:scenario Get the actionable pending actions when the queue is sparse
     * @custom:given 3 users have initiated a deposit
     * @custom:and The first and second pending actions have been manually removed from the queue
     * @custom:when The actionable pending actions are requested
     * @custom:then The third pending action is returned
     */
    function test_getActionablePendingActionsSparse() public {
        _setupSparsePendingActionsQueue();

        // Wait
        skip(protocol.getValidationDeadline() + 1);

        (PendingAction[] memory actions, uint128[] memory rawIndices) = protocol.getActionablePendingActions(address(0));
        assertEq(actions.length, 2, "actions length");
        assertEq(actions[1].user, USER_3, "user");
        assertEq(rawIndices[1], 2, "raw index");
    }

    /**
     * @custom:scenario Get the first actionable pending action when the queue is sparse
     * @custom:given 3 users have initiated a deposit
     * @custom:and The first and second pending actions have been manually removed from the queue
     * @custom:when The first actionable pending action is requested
     * @custom:then No actionable pending action is returned
     */
    function test_internalGetActionablePendingActionSparse() public {
        _setupSparsePendingActionsQueue();

        // Wait
        skip(protocol.getValidationDeadline() + 1);

        (PendingAction memory action, uint128 rawIndex) = protocol.i_getActionablePendingAction();
        assertTrue(action.user == USER_3, "user");
        assertEq(rawIndex, 2, "raw index");
    }

    /**
     * @custom:scenario Get the actionable pending actions when the queue is empty
     * @custom:given The queue is empty
     * @custom:when The actionable pending actions are requested
     * @custom:then No actionable pending action is returned
     */
    function test_getActionablePendingActionEmpty() public {
        (PendingAction[] memory actions,) = protocol.getActionablePendingActions(address(0));
        assertEq(actions.length, 0, "empty list");
    }

    /**
     * @custom:scenario Get the first actionable pending action when the queue is empty
     * @custom:given The queue is empty
     * @custom:when The first actionable pending action is requested
     * @custom:then No actionable pending action is returned
     */
    function test_internalGetActionablePendingActionEmpty() public {
        (PendingAction memory action, uint128 rawIndex) = protocol.i_getActionablePendingAction();
        assertEq(action.user, address(0), "action user");
        assertEq(rawIndex, 0, "raw index");
    }

    /**
     * @custom:scenario User who didn't validate their tx after 1 hour and call `getActionablePendingAction`
     * @custom:background When a user have their own action in the first position in the queue and it's actionable by
     * someone else, they should retrieve the next item in the queue at the moment of validating their own action.
     * This is because they will remove their own action from the queue before attempting to validate the next item in
     * the queue, and it would revert if they provided the price data for their own actionable pending action.
     * @custom:given The user has initiated a long and waited the validation deadline duration
     * @custom:and Their transaction is still the first in the queue
     * @custom:when They call `getActionablePendingAction`
     * @custom:then Their pending action in the queue is skipped and not returned
     */
    function test_getActionablePendingActionSameUser() public {
        // initiate long
        setUpUserPositionInLong(address(this), ProtocolAction.InitiateOpenPosition, 3 ether, 1000 ether, 2000 ether);
        // the pending action is actionable after the validation deadline
        skip(protocol.getValidationDeadline() + 1);
        (PendingAction[] memory actions, uint128[] memory rawIndices) = protocol.getActionablePendingActions(address(0));
        assertEq(actions.length, 1, "actions length");
        assertEq(actions[0].user, address(this), "action user");
        assertEq(rawIndices[0], 0, "action rawIndex");
        // but if the user himself calls the function, the action should not be returned
        (actions, rawIndices) = protocol.getActionablePendingActions(address(this));
        assertEq(actions.length, 0, "no action");
    }

    /**
     * @custom:scenario Validate a user's pending position which is actionable at the same time as another user's
     * pending action.
     * @custom:given Two users have initiated deposits
     * @custom:and The validation deadline has elapsed for both of them
     * @custom:when The second user validates their pending position
     * @custom:then Both positions are validated
     */
    function test_twoPending() public {
        uint128 price1 = 2000 ether;
        uint128 price2 = 2100 ether;
        // Setup 2 pending actions
        setUpUserPositionInLong(USER_1, ProtocolAction.InitiateOpenPosition, 3 ether, 1000 ether, price1);
        setUpUserPositionInLong(USER_2, ProtocolAction.InitiateOpenPosition, 3 ether, 1000 ether, price2);

        // Wait
        skip(protocol.getValidationDeadline() + 1);

        // Second user tries to validate their action
        vm.prank(USER_2);
        bytes[] memory previousData = new bytes[](1);
        previousData[0] = abi.encode(price1);
        uint128[] memory rawIndices = new uint128[](1);
        rawIndices[0] = 0;
        protocol.validateOpenPosition(abi.encode(price2), PreviousActionsData(previousData, rawIndices));
        // No more pending action
        (PendingAction[] memory actions,) = protocol.getActionablePendingActions(address(0));
        assertEq(actions.length, 0, "no action");
        (PendingAction memory action,) = protocol.i_getActionablePendingAction();
        assertTrue(action.action == ProtocolAction.None, "no action (internal)");
    }

    /**
     * @custom:scenario Two actionable pending actions are validated by two other users in the same block
     * @custom:given Two users have initiated deposits and the deadline has elapsed
     * @custom:when Two other users validate the pending actions in the same block
     * @custom:then Both positions are validated with different prices and there are no reverts
     */
    function test_twoUsersValidatingInSameBlock() public {
        uint128 price1 = 2000 ether;
        uint128 price2 = 2100 ether;

        uint256 user1BalanceBefore = usdn.balanceOf(USER_1);
        uint256 user2BalanceBefore = usdn.balanceOf(USER_2);

        // Setup 2 pending actions
        setUpUserPositionInVault(USER_1, ProtocolAction.InitiateDeposit, 3 ether, price1);
        setUpUserPositionInVault(USER_2, ProtocolAction.InitiateDeposit, 3 ether, price2);

        // Wait
        skip(protocol.getValidationDeadline() + 1);

        // Two other users want to now enter the protocol
        wstETH.mintAndApprove(USER_3, 100_000 ether, address(protocol), type(uint256).max);
        wstETH.mintAndApprove(USER_4, 100_000 ether, address(protocol), type(uint256).max);
        (PendingAction[] memory actions, uint128[] memory rawIndices) = protocol.getActionablePendingActions(address(0));
        assertEq(actions.length, 2, "actions length");
        bytes[] memory previousPriceData = new bytes[](actions.length);
        previousPriceData[0] = abi.encode(price1);
        previousPriceData[1] = abi.encode(price2);
        PreviousActionsData memory previousActionsData =
            PreviousActionsData({ priceData: previousPriceData, rawIndices: rawIndices });
        vm.prank(USER_3);
        protocol.initiateDeposit(3 ether, abi.encode(2200 ether), previousActionsData);
        vm.prank(USER_4);
        protocol.initiateDeposit(3 ether, abi.encode(2200 ether), previousActionsData);

        // They should have validated both pending actions
        (actions, rawIndices) = protocol.getActionablePendingActions(address(0));
        assertEq(actions.length, 0, "final actions length");

        // We indeed validated with different price data
        assertTrue(
            usdn.balanceOf(USER_1) - user1BalanceBefore != usdn.balanceOf(USER_2) - user2BalanceBefore,
            "user 1 and 2 have different minted amount"
        );
    }

    /**
     * @custom:scenario Convert an untyped pending action into a vault pending action
     * @custom:given An untyped `PendingAction`
     * @custom:when The action is converted to a `VaultPendingAction` and back into a `PendingAction`
     * @custom:then The original and the converted `PendingAction` are equal
     */
    function test_internalConvertVaultPendingAction() public {
        PendingAction memory action = PendingAction({
            action: ProtocolAction.ValidateDeposit,
            timestamp: uint40(block.timestamp),
            user: address(this),
            var1: 0, // must be zero because unused
            amount: 42,
            var2: 69,
            var3: 420,
            var4: 1337,
            var5: 9000,
            var6: 23
        });
        VaultPendingAction memory vaultAction = protocol.i_toVaultPendingAction(action);
        assertTrue(vaultAction.action == action.action, "action action");
        assertEq(vaultAction.timestamp, action.timestamp, "action timestamp");
        assertEq(vaultAction.user, action.user, "action user");
        assertEq(vaultAction.amount, action.amount, "action amount");
        assertEq(vaultAction.assetPrice, action.var2, "action price");
        assertEq(vaultAction.totalExpo, action.var3, "action expo");
        assertEq(vaultAction.balanceVault, action.var4, "action balance vault");
        assertEq(vaultAction.balanceLong, action.var5, "action balance long");
        assertEq(vaultAction.usdnTotalSupply, action.var6, "action total supply");
        PendingAction memory result = protocol.i_convertVaultPendingAction(vaultAction);
        _assertActionsEqual(action, result, "vault pending action conversion");
    }

    /**
     * @custom:scenario Convert an untyped pending action into a long pending action
     * @custom:given An untyped `PendingAction`
     * @custom:when The action is converted to a `LongPendingAction` and back into a `PendingAction`
     * @custom:then The original and the converted `PendingAction` are equal
     */
    function test_internalConvertLongPendingAction() public {
        PendingAction memory action = PendingAction({
            action: ProtocolAction.ValidateOpenPosition,
            timestamp: uint40(block.timestamp),
            user: address(this),
            var1: 2398,
            amount: 42,
            var2: 69,
            var3: 420,
            var4: 1337,
            var5: 9000,
            var6: 23
        });
        LongPendingAction memory longAction = protocol.i_toLongPendingAction(action);
        assertTrue(longAction.action == action.action, "action action");
        assertEq(longAction.timestamp, action.timestamp, "action timestamp");
        assertEq(longAction.user, action.user, "action user");
        assertEq(longAction.tick, action.var1, "action tick");
        assertEq(longAction.closeAmount, action.amount, "action amount");
        assertEq(longAction.closeTotalExpo, action.var2, "action total expo");
        assertEq(longAction.tickVersion, action.var3, "action version");
        assertEq(longAction.index, action.var4, "action index");
        assertEq(longAction.closeLiqMultiplier, action.var5, "action multiplier");
        assertEq(longAction.closeTempTransfer, action.var6, "action transfer");
        PendingAction memory result = protocol.i_convertLongPendingAction(longAction);
        _assertActionsEqual(action, result, "long pending action conversion");
    }
}

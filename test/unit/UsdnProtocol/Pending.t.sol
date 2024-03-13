// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { UsdnProtocolBaseFixture } from "test/unit/UsdnProtocol/utils/Fixtures.sol";
import { USER_1, USER_2, USER_3 } from "test/utils/Constants.sol";

import {
    PendingAction,
    VaultPendingAction,
    LongPendingAction,
    ProtocolAction
} from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";

/**
 * @custom:feature The functions handling the pending actions queue
 * @custom:background Given a protocol instance that was initialized with default params
 */
contract TestUsdnProtocolPending is UsdnProtocolBaseFixture {
    function setUp() public {
        super._setUp(DEFAULT_PARAMS);
    }

    /**
     * @dev Helper to test the functionality of `getActionablePendingAction` and `i_getActionablePendingAction`
     * @param func The function to call
     */
    function _getActionablePendingActionHelper(function (uint256) external returns (PendingAction memory) func)
        internal
    {
        wstETH.mintAndApprove(address(this), 100_000 ether, address(protocol), type(uint256).max);
        // there should be no pending action at this stage
        PendingAction memory action = func(0);
        assertTrue(action.action == ProtocolAction.None, "pending action before initiate");
        // initiate long
        bytes memory priceData = abi.encode(2000 ether);
        protocol.initiateOpenPosition(1 ether, 1000 ether, priceData, "");
        // the pending action is not yet actionable
        vm.prank(address(0)); // simulate front-end call by someone else
        action = func(0);
        assertTrue(action.action == ProtocolAction.None, "pending action after initiate");
        // the pending action is actionable after the validation deadline
        skip(protocol.getValidationDeadline() + 1);
        vm.prank(address(0)); // simulate front-end call by someone else
        action = func(0);
        assertEq(action.user, address(this), "action user");
    }

    /**
     * @custom:scenario Get the first actionable pending action
     * @custom:given The user has initiated a deposit
     * @custom:and The validation deadline has elapsed
     * @custom:when The first actionable pending action is requested
     * @custom:then The pending action is returned
     */
    function test_getActionablePendingAction() public {
        _getActionablePendingActionHelper(protocol.getActionablePendingAction);
    }

    /**
     * @custom:scenario Get the first actionable pending action
     * @custom:given The user has initiated a deposit
     * @custom:and The validation deadline has elapsed
     * @custom:when The first actionable pending action is requested
     * @custom:then The pending action is returned
     */
    function test_internalGetActionablePendingAction() public {
        _getActionablePendingActionHelper(protocol.i_getActionablePendingAction);
    }

    /**
     * @dev Helper to test the functionality of `getActionablePendingAction` and `i_getActionablePendingAction` when the
     * queue is sparsely populated
     * @param func The function to call
     */
    function _getActionablePendingActionSparseHelper(function (uint256) external returns (PendingAction memory) func)
        internal
    {
        wstETH.mint(USER_1, 100_000 ether);
        wstETH.mint(USER_2, 100_000 ether);
        wstETH.mint(USER_3, 100_000 ether);
        bytes memory priceData = abi.encode(2000 ether);
        // Setup 3 pending actions
        vm.startPrank(USER_1);
        wstETH.approve(address(protocol), type(uint256).max);
        protocol.initiateOpenPosition(1 ether, 1000 ether, priceData, "");
        vm.stopPrank();
        vm.startPrank(USER_2);
        wstETH.approve(address(protocol), type(uint256).max);
        protocol.initiateOpenPosition(1 ether, 1000 ether, priceData, "");
        vm.stopPrank();
        vm.startPrank(USER_3);
        wstETH.approve(address(protocol), type(uint256).max);
        protocol.initiateOpenPosition(1 ether, 1000 ether, priceData, "");
        vm.stopPrank();

        // Simulate the second item in the queue being empty (sets it to zero values)
        protocol.i_removePendingAction(1, USER_2);
        // Simulate the first item in the queue being empty
        // This will pop the first item, but leave the second empty
        protocol.i_removePendingAction(0, USER_1);

        // Wait
        skip(protocol.getValidationDeadline() + 1);

        // With 1 max iter, we should not get any pending action (since the first item in the queue is zeroed)
        PendingAction memory action = func(1);
        assertEq(action.user, address(0), "max iter 1");
        // With 2 max iter, we should get the action corresponding to the third user, which is actionable
        action = func(2);
        assertTrue(action.user == USER_3, "max iter 2");
    }

    /**
     * @custom:scenario Get the first actionable pending action when the queue is sparse
     * @custom:given 3 users have initiated a deposit
     * @custom:and The first and second pending actions have been manually removed from the queue
     * @custom:when The first actionable pending action is requested with a max iter of 1
     * @custom:or The first actionable pending action is requested with a max iter of 2
     * @custom:then No actionable pending action is returned with a max iter of 1
     * @custom:or The third pending action is returned with a max iter of 2
     */
    function test_getActionablePendingActionSparse() public {
        _getActionablePendingActionSparseHelper(protocol.getActionablePendingAction);
    }

    /**
     * @custom:scenario Get the first actionable pending action when the queue is sparse
     * @custom:given 3 users have initiated a deposit
     * @custom:and The first and second pending actions have been manually removed from the queue
     * @custom:when The first actionable pending action is requested with a max iter of 1
     * @custom:or The first actionable pending action is requested with a max iter of 2
     * @custom:then No actionable pending action is returned with a max iter of 1
     * @custom:or The third pending action is returned with a max iter of 2
     */
    function test_internalGetActionablePendingActionSparse() public {
        _getActionablePendingActionSparseHelper(protocol.i_getActionablePendingAction);
    }

    /**
     * @dev Helper to test the functionality of `getActionablePendingAction` and `i_getActionablePendingAction` when the
     * queue is empty
     * @param func The function to call
     */
    function _getActionablePendingActionEmptyHelper(function (uint256) external returns (PendingAction memory) func)
        internal
    {
        PendingAction memory action = func(0);
        assertEq(action.user, address(0));
    }

    /**
     * @custom:scenario Get the first actionable pending action when the queue is empty
     * @custom:given The queue is empty
     * @custom:when The first actionable pending action is requested
     * @custom:then No actionable pending action is returned
     */
    function test_getActionablePendingActionEmpty() public {
        _getActionablePendingActionEmptyHelper(protocol.getActionablePendingAction);
    }

    /**
     * @custom:scenario Get the first actionable pending action when the queue is empty
     * @custom:given The queue is empty
     * @custom:when The first actionable pending action is requested
     * @custom:then No actionable pending action is returned
     */
    function test_internalGetActionablePendingActionEmpty() public {
        _getActionablePendingActionEmptyHelper(protocol.i_getActionablePendingAction);
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
        wstETH.mint(address(this), 100_000 ether);
        wstETH.approve(address(protocol), type(uint256).max);
        // initiate long
        bytes memory priceData = abi.encode(2000 ether);
        protocol.initiateOpenPosition(1 ether, 1000 ether, priceData, "");
        // the pending action is actionable after the validation deadline
        skip(protocol.getValidationDeadline() + 1);
        vm.prank(address(0)); // simulate front-end call by someone else
        PendingAction memory action = protocol.getActionablePendingAction(0);
        assertEq(action.user, address(this), "action user");
        // but if the user himself calls the function, the action should not be returned
        action = protocol.getActionablePendingAction(0);
        assertEq(action.user, address(0), "action user");
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

    /**
     * @custom:scenario Validate a user's pending position which is actionable at the same time as another user's
     * pending action.
     * @custom:given Two users have initiated deposits
     * @custom:and The validation deadline has elapsed for both of them
     * @custom:when The second user validates their pending position
     * @custom:then Both positions are validated
     */
    function test_twoPending() public {
        wstETH.mint(USER_1, 100_000 ether);
        wstETH.mint(USER_2, 100_000 ether);
        bytes memory data1 = abi.encode(2000 ether);
        bytes memory data2 = abi.encode(2100 ether);
        // Setup 2 pending actions
        vm.startPrank(USER_1);
        wstETH.approve(address(protocol), type(uint256).max);
        protocol.initiateOpenPosition(1 ether, 1000 ether, data1, "");
        vm.stopPrank();
        skip(30);
        vm.startPrank(USER_2);
        wstETH.approve(address(protocol), type(uint256).max);
        protocol.initiateOpenPosition(1 ether, 1000 ether, data2, "");
        vm.stopPrank();

        // Wait
        skip(protocol.getValidationDeadline() + 1);

        // Second user tries to validate their action
        vm.prank(USER_2);
        protocol.validateOpenPosition(data2, data1);
        // No more pending action
        PendingAction memory action = protocol.getActionablePendingAction(0);
        assertEq(action.user, address(0));
    }
}

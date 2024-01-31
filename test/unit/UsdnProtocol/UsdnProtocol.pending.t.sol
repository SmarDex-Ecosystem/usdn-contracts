// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { FixedPointMathLib } from "solady/src/utils/FixedPointMathLib.sol";

import { UsdnProtocolBaseFixture } from "test/unit/UsdnProtocol/utils/Fixtures.sol";
import { USER_1, USER_2, USER_3 } from "test/utils/Constants.sol";

import { PendingAction, ProtocolAction } from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";

/**
 * @custom:feature The functions handling the pending actions queue
 * @custom:background Given a protocol instance that was initialized with 2 longs and 1 short
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
        wstETH.mint(address(this), 100_000 ether);
        wstETH.approve(address(protocol), type(uint256).max);
        // there should be no pending action at this stage
        PendingAction memory action = func(0);
        assertTrue(action.action == ProtocolAction.None, "pending action before initiate");
        // initiate long
        protocol.initiateOpenPosition(1 ether, 1000 ether, abi.encode(2000 ether), "");
        // the pending action is not yet actionable
        action = func(0);
        assertTrue(action.action == ProtocolAction.None, "pending action after initiate");
        // the pending action is actionable after the validation deadline
        skip(protocol.validationDeadline() + 1);
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
        // Setup 3 pending actions
        vm.startPrank(USER_1);
        wstETH.approve(address(protocol), type(uint256).max);
        protocol.initiateOpenPosition(1 ether, 1000 ether, abi.encode(2000 ether), "");
        vm.stopPrank();
        vm.startPrank(USER_2);
        wstETH.approve(address(protocol), type(uint256).max);
        protocol.initiateOpenPosition(1 ether, 1000 ether, abi.encode(2000 ether), "");
        vm.stopPrank();
        vm.startPrank(USER_3);
        wstETH.approve(address(protocol), type(uint256).max);
        protocol.initiateOpenPosition(1 ether, 1000 ether, abi.encode(2000 ether), "");
        vm.stopPrank();

        // Simulate the second item in the queue being empty (sets it to zero values)
        protocol.removePendingAction(1, USER_2);
        // Simulate the first item in the queue being empty
        // This will pop the first item, but leave the second empty
        protocol.removePendingAction(0, USER_1);

        // Wait
        skip(protocol.validationDeadline() + 1);

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
}

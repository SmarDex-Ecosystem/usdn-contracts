// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { ADMIN, USER_1 } from "../../../utils/Constants.sol";
import { UsdnProtocolBaseFixture } from "../utils/Fixtures.sol";

import { DoubleEndedQueue } from "../../../../src/libraries/DoubleEndedQueue.sol";
import { HugeUint } from "../../../../src/libraries/HugeUint.sol";

/// @custom:feature The `removeBlockedPendingAction` and `_removeBlockedPendingAction` admin functions of the protocol
contract TestUsdnProtocolRemoveBlockedPendingAction is UsdnProtocolBaseFixture {
    /// @dev Whether to revert inside the receive function of this contract
    bool revertOnReceive = false;

    function setUp() public {
        params = DEFAULT_PARAMS;
        params.flags.enableSecurityDeposit = true;
        super._setUp(params);
    }

    /* -------------------------------------------------------------------------- */
    /*                                With rawIndex                               */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice Helper function to setup a vault pending action and remove it with the admin function
     * @param untilAction Whether to initiate a deposit or a withdrawal
     * @param amount The amount to deposit
     * @param cleanup Whether to remove the action with more cleanup
     * @param ext Whether to call the external function (false for the internal one)
     */
    function _removeBlockedVaultScenario(ProtocolAction untilAction, uint128 amount, bool cleanup, bool ext) internal {
        setUpUserPositionInVault(USER_1, untilAction, amount, params.initialPrice);
        _wait();

        (, uint128 rawIndex) = protocol.i_getPendingAction(USER_1);

        vm.prank(ADMIN);
        if (ext && cleanup) {
            protocol.removeBlockedPendingAction(rawIndex, payable(this));
        } else if (ext && !cleanup) {
            protocol.removeBlockedPendingActionNoCleanup(rawIndex, payable(this));
        } else {
            protocol.i_removeBlockedPendingAction(rawIndex, payable(this), cleanup);
        }

        assertTrue(protocol.getUserPendingAction(USER_1).action == ProtocolAction.None, "pending action");
        vm.expectRevert(DoubleEndedQueue.QueueOutOfBounds.selector);
        protocol.getQueueItem(rawIndex);
    }

    /**
     * @custom:scenario Remove a stuck deposit with cleanup
     * @custom:given A user has initiated a deposit which gets stuck for any reason
     * @custom:when The admin removes the pending action with cleanup
     * @custom:then The pending action is removed
     * @custom:and The `to` address receives the deposited assets and the security deposit
     * @custom:and The pending vault balance is decremented
     */
    function test_removeBlockedDepositCleanup() public {
        uint256 balanceBefore = address(this).balance;
        uint256 assetBalanceBefore = wstETH.balanceOf(address(this));
        _removeBlockedVaultScenario(ProtocolAction.InitiateDeposit, 10 ether, true, true);
        assertEq(wstETH.balanceOf(address(this)), assetBalanceBefore + 10 ether, "asset balance after");
        assertEq(address(this).balance, balanceBefore + protocol.getSecurityDepositValue(), "balance after");
        assertEq(protocol.getPendingBalanceVault(), 0, "pending vault balance");
    }

    /**
     * @custom:scenario Remove a stuck deposit with cleanup
     * @custom:given A user has initiated a deposit which gets stuck for any reason
     * @custom:when We remove the pending action with cleanup with the internal function
     * @custom:then The pending action is removed
     * @custom:and The `to` address receives the deposited assets and the security deposit
     * @custom:and The pending vault balance is decremented
     */
    function test_removeBlockedDepositCleanupInternal() public {
        uint256 balanceBefore = address(this).balance;
        uint256 assetBalanceBefore = wstETH.balanceOf(address(this));
        _removeBlockedVaultScenario(ProtocolAction.InitiateDeposit, 10 ether, true, false);
        assertEq(wstETH.balanceOf(address(this)), assetBalanceBefore + 10 ether, "asset balance after");
        assertEq(address(this).balance, balanceBefore + protocol.getSecurityDepositValue(), "balance after");
        assertEq(protocol.getPendingBalanceVault(), 0, "pending vault balance");
    }

    /**
     * @custom:scenario Remove a stuck deposit without cleanup
     * @custom:given A user has initiated a deposit which gets stuck for any reason
     * @custom:when The admin removes the pending action without cleanup
     * @custom:then The pending action is removed
     * @custom:and The `to` address does not receive any assets or security deposit
     * @custom:and The pending vault balance remains unchanged
     */
    function test_removeBlockedDepositNoCleanup() public {
        uint256 balanceBefore = address(this).balance;
        uint256 assetBalanceBefore = wstETH.balanceOf(address(this));
        _removeBlockedVaultScenario(ProtocolAction.InitiateDeposit, 10 ether, false, true);
        assertEq(wstETH.balanceOf(address(this)), assetBalanceBefore, "asset balance after");
        assertEq(address(this).balance, balanceBefore, "balance after");
        assertEq(protocol.getPendingBalanceVault(), 10 ether, "pending vault balance");
    }

    /**
     * @custom:scenario Remove a stuck deposit without cleanup
     * @custom:given A user has initiated a deposit which gets stuck for any reason
     * @custom:when We remove the pending action without cleanup with the internal function
     * @custom:then The pending action is removed
     * @custom:and The `to` address does not receive any assets or security deposit
     * @custom:and The pending vault balance remains unchanged
     */
    function test_removeBlockedDepositNoCleanupInternal() public {
        uint256 balanceBefore = address(this).balance;
        uint256 assetBalanceBefore = wstETH.balanceOf(address(this));
        _removeBlockedVaultScenario(ProtocolAction.InitiateDeposit, 10 ether, false, false);
        assertEq(wstETH.balanceOf(address(this)), assetBalanceBefore, "asset balance after");
        assertEq(address(this).balance, balanceBefore, "balance after");
        assertEq(protocol.getPendingBalanceVault(), 10 ether, "pending vault balance");
    }

    /**
     * @custom:scenario Remove a stuck withdrawal with cleanup
     * @custom:given A user has initiated a withdrawal which gets stuck for any reason
     * @custom:when The admin removes the pending action with cleanup
     * @custom:then The pending action is removed
     * @custom:and The `to` address receives the USDN and the security deposit
     * @custom:and The pending vault balance is incremented
     */
    function test_removeBlockedWithdrawalCleanup() public {
        uint256 balanceBefore = address(this).balance;
        uint256 usdnBalanceBefore = usdn.balanceOf(address(this));
        _removeBlockedVaultScenario(ProtocolAction.InitiateWithdrawal, 10 ether, true, false);
        assertEq(usdn.balanceOf(address(this)), usdnBalanceBefore + 20_000 ether, "usdn balance after");
        assertEq(address(this).balance, balanceBefore + protocol.getSecurityDepositValue(), "balance after");
        assertEq(protocol.getPendingBalanceVault(), 0, "pending vault balance");
    }

    /**
     * @custom:scenario Remove a stuck withdrawal without cleanup
     * @custom:given A user has initiated a withdrawal which gets stuck for any reason
     * @custom:when The admin removes the pending action without cleanup
     * @custom:then The pending action is removed
     * @custom:and The `to` address does not receive any USDN or security deposit
     * @custom:and The pending vault balance remains unchanged
     */
    function test_removeBlockedWithdrawalNoCleanup() public {
        uint256 balanceBefore = address(this).balance;
        uint256 usdnBalanceBefore = usdn.balanceOf(address(this));
        _removeBlockedVaultScenario(ProtocolAction.InitiateWithdrawal, 10 ether, false, false);
        assertEq(usdn.balanceOf(address(this)), usdnBalanceBefore, "usdn balance after");
        assertEq(address(this).balance, balanceBefore, "balance after");
        assertEq(protocol.getPendingBalanceVault(), -10 ether, "pending vault balance");
    }

    /**
     * @notice Helper function to setup a long side pending action and remove it with the admin function
     * @param untilAction Whether to initiate an open or a close position
     * @param amount The amount of collateral
     * @param cleanup Whether to remove the action with more cleanup
     */
    function _removeBlockedLongScenario(ProtocolAction untilAction, uint128 amount, bool cleanup)
        internal
        returns (PositionId memory posId_)
    {
        posId_ = setUpUserPositionInLong(
            OpenParams({
                user: USER_1,
                untilAction: untilAction,
                positionSize: amount,
                desiredLiqPrice: params.initialPrice / 2,
                price: params.initialPrice
            })
        );
        _wait();

        (, uint128 rawIndex) = protocol.i_getPendingAction(USER_1);

        vm.prank(ADMIN);
        protocol.i_removeBlockedPendingAction(rawIndex, payable(this), cleanup);

        assertTrue(protocol.getUserPendingAction(USER_1).action == ProtocolAction.None, "pending action");
        vm.expectRevert(DoubleEndedQueue.QueueOutOfBounds.selector);
        protocol.getQueueItem(rawIndex);

        (Position memory pos,) = protocol.getLongPosition(posId_);
        assertEq(pos.user, address(0), "pos user");
    }

    /**
     * @custom:scenario Remove a stuck open position with cleanup
     * @custom:given A user has initiated an open position which gets stuck for any reason
     * @custom:when The admin removes the pending action with cleanup
     * @custom:then The pending action is removed
     * @custom:and The protocol state is updated to remove the position
     */
    function test_removeBlockedOpenPositionCleanup() public {
        uint256 balanceBefore = address(this).balance;
        int24 expectedTick = protocol.getEffectiveTickForPrice(params.initialPrice / 2);
        TickData memory tickDataBefore = protocol.getTickData(expectedTick);
        uint256 totalPosBefore = protocol.getTotalLongPositions();
        HugeUint.Uint512 memory accBefore = protocol.getLiqMultiplierAccumulator();
        uint256 totalExpoBefore = protocol.getTotalExpo();

        PositionId memory posId = _removeBlockedLongScenario(ProtocolAction.InitiateOpenPosition, 10 ether, true);
        assertEq(posId.tick, expectedTick, "expected tick");

        TickData memory tickDataAfter = protocol.getTickData(posId.tick);
        assertEq(tickDataAfter.totalExpo, tickDataBefore.totalExpo, "tick total expo");
        assertEq(tickDataAfter.totalPos, tickDataBefore.totalPos, "tick total pos");
        assertEq(tickDataAfter.totalPos, 0, "no more pos in tick");
        assertFalse(protocol.tickBitmapStatus(posId.tick), "tick bitmap status");

        assertEq(protocol.getTotalLongPositions(), totalPosBefore, "total pos");

        HugeUint.Uint512 memory accAfter = protocol.getLiqMultiplierAccumulator();
        assertEq(accAfter.hi, accBefore.hi, "accumulator hi");
        assertEq(accAfter.lo, accBefore.lo, "accumulator lo");

        assertEq(protocol.getTotalExpo(), totalExpoBefore, "total expo");

        assertEq(address(this).balance, balanceBefore + protocol.getSecurityDepositValue(), "balance after");
    }

    /**
     * @custom:scenario Remove a stuck open position without cleanup
     * @custom:given A user has initiated an open position which gets stuck for any reason
     * @custom:when The admin removes the pending action without cleanup
     * @custom:then The pending action is removed
     * @custom:and The protocol state is not updated
     */
    function test_removeBlockedOpenPositionNoCleanup() public {
        uint256 balanceBefore = address(this).balance;
        uint256 totalPosBefore = protocol.getTotalLongPositions();
        uint256 totalExpoBefore = protocol.getTotalExpo();

        _removeBlockedLongScenario(ProtocolAction.InitiateOpenPosition, 10 ether, false);

        assertEq(protocol.getTotalLongPositions(), totalPosBefore + 1, "total pos");
        assertGt(protocol.getTotalExpo(), totalExpoBefore, "total expo");

        assertEq(address(this).balance, balanceBefore, "balance after");
    }

    /**
     * @custom:scenario Remove a stuck close position with cleanup
     * @custom:given A user has initiated a close position which gets stuck for any reason
     * @custom:when The admin removes the pending action with cleanup
     * @custom:then The pending action is removed
     * @custom:and The protocol balances are updated to cleanup the position
     * @custom:and The `to` address receives the the security deposit
     */
    function test_removeBlockedClosePositionCleanup() public {
        uint256 balanceBefore = address(this).balance;
        uint256 balanceLongBefore = protocol.getBalanceLong();
        uint256 balanceVaultBefore = protocol.getBalanceVault();

        _removeBlockedLongScenario(ProtocolAction.InitiateClosePosition, 10 ether, true);

        assertApproxEqAbs(protocol.getBalanceLong(), balanceLongBefore, 1, "balance long");
        assertApproxEqAbs(protocol.getBalanceVault(), balanceVaultBefore + 10 ether, 1, "balance vault");
        assertEq(
            protocol.getBalanceLong() + protocol.getBalanceVault(),
            balanceLongBefore + balanceVaultBefore + 10 ether,
            "total balance"
        );

        assertEq(address(this).balance, balanceBefore + protocol.getSecurityDepositValue(), "balance after");
    }

    /**
     * @custom:scenario Remove a stuck close position without cleanup
     * @custom:given A user has initiated a close position which gets stuck for any reason
     * @custom:when The admin removes the pending action without cleanup
     * @custom:then The pending action is removed
     * @custom:and The protocol balances are not updated
     * @custom:and The `to` address does not receive any security deposit
     */
    function test_removeBlockedClosePositionNoCleanup() public {
        uint256 balanceBefore = address(this).balance;
        uint256 balanceLongBefore = protocol.getBalanceLong();
        uint256 balanceVaultBefore = protocol.getBalanceVault();

        _removeBlockedLongScenario(ProtocolAction.InitiateClosePosition, 10 ether, false);

        // during the initiateClosePosition, we optimistically decrease the long balance by the position value
        // (10 ether +- 1 wei) which we do not add back to any balances since we are doing the safe fix

        assertApproxEqAbs(protocol.getBalanceLong(), balanceLongBefore, 1, "balance long");
        assertApproxEqAbs(protocol.getBalanceVault(), balanceVaultBefore, 1, "balance vault");
        assertApproxEqAbs(
            protocol.getBalanceLong() + protocol.getBalanceVault(),
            balanceLongBefore + balanceVaultBefore,
            1,
            "total balance"
        );

        assertEq(address(this).balance, balanceBefore, "balance after");
    }

    /**
     * @custom:scenario The admin tries to remove a blocked pending action too soon
     * @custom:given A user has initiated a deposit which gets stuck for any reason
     * @custom:when The admin tries to remove the pending action after the validation delay
     * @custom:or The admin tries to remove the pending action after the validation deadline
     * @custom:or The admin tries to remove the pending action after the validation deadline + 1 hour - 1 second
     * @custom:then The transaction reverts with the `UsdnProtocolUnauthorized` error
     */
    function test_RevertWhen_removeBlockedTooSoon() public {
        setUpUserPositionInVault(USER_1, ProtocolAction.InitiateDeposit, 1 ether, params.initialPrice);
        vm.startPrank(ADMIN);
        (PendingAction memory action, uint128 rawIndex) = protocol.i_getPendingAction(USER_1);

        _waitDelay();

        vm.expectRevert(UsdnProtocolUnauthorized.selector);
        protocol.i_removeBlockedPendingAction(rawIndex, payable(this), true);

        _waitBeforeActionablePendingAction();

        vm.expectRevert(UsdnProtocolUnauthorized.selector);
        protocol.i_removeBlockedPendingAction(rawIndex, payable(this), true);

        vm.warp(action.timestamp + protocol.getLowLatencyValidationDeadline() + 3599 seconds);

        vm.expectRevert(UsdnProtocolUnauthorized.selector);
        protocol.i_removeBlockedPendingAction(rawIndex, payable(this), true);
        vm.stopPrank();
    }

    /**
     * @custom:scenario The admin tries to remove a blocked pending action with cleanup but refund fails
     * @custom:given The "to" address reverts when receiving the assets
     * @custom:when The admin tries to remove the pending action with cleanup
     * @custom:then The transaction reverts with the `UsdnProtocolEtherRefundFailed` error
     */
    function test_RevertWhen_removeBlockedRefundFailed() public {
        setUpUserPositionInVault(USER_1, ProtocolAction.InitiateDeposit, 1 ether, params.initialPrice);
        revertOnReceive = true;

        _wait();

        (, uint128 rawIndex) = protocol.i_getPendingAction(USER_1);

        vm.expectRevert(UsdnProtocolEtherRefundFailed.selector);
        vm.prank(ADMIN);
        protocol.i_removeBlockedPendingAction(rawIndex, payable(this), true);
    }

    /* -------------------------------------------------------------------------- */
    /*                               With validator                               */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice Helper function to setup a vault pending action and remove it with the admin function with validator
     * @param untilAction Whether to initiate a deposit or a withdrawal
     * @param amount The amount to deposit
     * @param cleanup Whether to remove the action with more cleanup
     */
    function _removeBlockedVaultScenario(ProtocolAction untilAction, uint128 amount, bool cleanup) internal {
        setUpUserPositionInVault(USER_1, untilAction, amount, params.initialPrice);
        _wait();

        vm.prank(ADMIN);
        if (cleanup) {
            protocol.removeBlockedPendingAction(USER_1, payable(this));
        } else {
            protocol.removeBlockedPendingActionNoCleanup(USER_1, payable(this));
        }

        assertTrue(protocol.getUserPendingAction(USER_1).action == ProtocolAction.None, "pending action");
    }

    /**
     * @custom:scenario Remove a stuck deposit with cleanup with validator
     * @custom:given A user has initiated a deposit which gets stuck for any reason
     * @custom:when The admin removes the pending action with cleanup
     * @custom:then The pending action is removed
     * @custom:and The `to` address receives the deposited assets and the security deposit
     * @custom:and The pending vault balance is decremented
     */
    function test_removeBlockedDepositCleanupWithValidator() public {
        uint256 balanceBefore = address(this).balance;
        uint256 assetBalanceBefore = wstETH.balanceOf(address(this));
        _removeBlockedVaultScenario(ProtocolAction.InitiateDeposit, 10 ether, true);
        assertEq(wstETH.balanceOf(address(this)), assetBalanceBefore + 10 ether, "asset balance after");
        assertEq(address(this).balance, balanceBefore + protocol.getSecurityDepositValue(), "balance after");
        assertEq(protocol.getPendingBalanceVault(), 0, "pending vault balance");
    }

    /**
     * @custom:scenario Remove a stuck deposit without cleanup with validator
     * @custom:given A user has initiated a deposit which gets stuck for any reason
     * @custom:when The admin removes the pending action without cleanup
     * @custom:then The pending action is removed
     * @custom:and The `to` address does not receive any assets or security deposit
     * @custom:and The pending vault balance remains unchanged
     */
    function test_removeBlockedDepositNoCleanupWithValidator() public {
        uint256 balanceBefore = address(this).balance;
        uint256 assetBalanceBefore = wstETH.balanceOf(address(this));
        _removeBlockedVaultScenario(ProtocolAction.InitiateDeposit, 10 ether, false);
        assertEq(wstETH.balanceOf(address(this)), assetBalanceBefore, "asset balance after");
        assertEq(address(this).balance, balanceBefore, "balance after");
        assertEq(protocol.getPendingBalanceVault(), 10 ether, "pending vault balance");
    }

    /**
     * @custom:scenario Remove a stuck withdrawal with cleanup with validator
     * @custom:given A user has initiated a withdrawal which gets stuck for any reason
     * @custom:when The admin removes the pending action with cleanup
     * @custom:then The pending action is removed
     * @custom:and The `to` address receives the USDN and the security deposit
     * @custom:and The pending vault balance is incremented
     */
    function test_removeBlockedWithdrawalCleanupWithValidator() public {
        uint256 balanceBefore = address(this).balance;
        uint256 usdnBalanceBefore = usdn.balanceOf(address(this));
        _removeBlockedVaultScenario(ProtocolAction.InitiateWithdrawal, 10 ether, true);
        assertEq(usdn.balanceOf(address(this)), usdnBalanceBefore + 20_000 ether, "usdn balance after");
        assertEq(address(this).balance, balanceBefore + protocol.getSecurityDepositValue(), "balance after");
        assertEq(protocol.getPendingBalanceVault(), 0, "pending vault balance");
    }

    /**
     * @custom:scenario Remove a stuck withdrawal without cleanup with validator
     * @custom:given A user has initiated a withdrawal which gets stuck for any reason
     * @custom:when The admin removes the pending action without cleanup
     * @custom:then The pending action is removed
     * @custom:and The `to` address does not receive any USDN or security deposit
     * @custom:and The pending vault balance remains unchanged
     */
    function test_removeBlockedWithdrawalNoCleanupWithValidator() public {
        uint256 balanceBefore = address(this).balance;
        uint256 usdnBalanceBefore = usdn.balanceOf(address(this));
        _removeBlockedVaultScenario(ProtocolAction.InitiateWithdrawal, 10 ether, false);
        assertEq(usdn.balanceOf(address(this)), usdnBalanceBefore, "usdn balance after");
        assertEq(address(this).balance, balanceBefore, "balance after");
        assertEq(protocol.getPendingBalanceVault(), -10 ether, "pending vault balance");
    }

    /**
     * @custom:scenario The admin tries to remove a blocked pending action but tx fails
     * @custom:given The protocol does not have pending actions for the user
     * @custom:when The admin tries to remove the pending action
     * @custom:then The transaction reverts with the `UsdnProtocolNoPendingAction` error
     */
    function test_RevertWhen_removeBlockedPendingActionWithoutPendingAction() public {
        vm.expectRevert(UsdnProtocolNoPendingAction.selector);
        vm.prank(ADMIN);
        protocol.removeBlockedPendingAction(payable(this), payable(this));
    }

    /**
     * @custom:scenario The admin tries to remove a blocked pending action but tx fails
     * @custom:given The protocol does not have pending actions for the user
     * @custom:when The admin tries to remove the pending action
     * @custom:then The transaction reverts with the `UsdnProtocolNoPendingAction` error
     */
    function test_RevertWhen_removeBlockedPendingActionNoCleanupWithoutPendingAction() public {
        vm.expectRevert(UsdnProtocolNoPendingAction.selector);
        vm.prank(ADMIN);
        protocol.removeBlockedPendingActionNoCleanup(payable(this), payable(this));
    }

    function _wait() internal {
        _waitBeforeActionablePendingAction();
        skip(1 hours);
    }

    receive() external payable {
        if (revertOnReceive) {
            revert();
        }
    }
}

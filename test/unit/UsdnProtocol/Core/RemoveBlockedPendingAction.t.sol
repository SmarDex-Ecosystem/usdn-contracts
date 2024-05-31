// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { UsdnProtocolBaseFixture } from "test/unit/UsdnProtocol/utils/Fixtures.sol";
import { ADMIN, USER_1 } from "test/utils/Constants.sol";

import { ProtocolAction, PositionId, Position, TickData } from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import { DoubleEndedQueue } from "src/libraries/DoubleEndedQueue.sol";
import { HugeUint } from "src/libraries/HugeUint.sol";

/// @custom:feature The `_removeBlockedPendingAction` admin function of the protocol
contract TestUsdnProtocolRemoveBlockedPendingAction is UsdnProtocolBaseFixture {
    function setUp() public {
        params = DEFAULT_PARAMS;
        params.flags.enableSecurityDeposit = true;
        super._setUp(params);
    }

    /**
     * @notice Helper function to setup a vault pending action and remove it with the admin function
     * @param untilAction Whether to initiate a deposit or a withdrawal
     * @param amount The amount to deposit
     * @param unsafe Whether to remove the action in an unsafe way
     */
    function _removeBlockedVaultScenario(ProtocolAction untilAction, uint128 amount, bool unsafe) internal {
        setUpUserPositionInVault(USER_1, untilAction, amount, params.initialPrice);
        _wait();

        (, uint128 rawIndex) = protocol.i_getPendingAction(USER_1);

        vm.prank(ADMIN);
        protocol.i_removeBlockedPendingAction(rawIndex, payable(address(this)), unsafe);

        assertTrue(protocol.getUserPendingAction(USER_1).action == ProtocolAction.None, "pending action");
        vm.expectRevert(DoubleEndedQueue.QueueOutOfBounds.selector);
        protocol.getQueueItem(rawIndex);
    }

    /**
     * @custom:scenario Remove a stuck deposit in an unsafe way
     * @custom:given A user has initiated a deposit which gets stuck for any reason
     * @custom:when The admin removes the pending action in an unsafe way
     * @custom:then The pending action is removed
     * @custom:and The `to` address receives the deposited assets and the security deposit
     */
    function test_removeBlockedDepositUnsafe() public {
        uint256 balanceBefore = address(this).balance;
        uint256 assetBalanceBefore = wstETH.balanceOf(address(this));
        _removeBlockedVaultScenario(ProtocolAction.InitiateDeposit, 10 ether, true);
        assertEq(wstETH.balanceOf(address(this)), assetBalanceBefore + 10 ether, "asset balance after");
        assertEq(address(this).balance, balanceBefore + protocol.getSecurityDepositValue(), "balance after");
    }

    /**
     * @custom:scenario Remove a stuck deposit in a safe way
     * @custom:given A user has initiated a deposit which gets stuck for any reason
     * @custom:when The admin removes the pending action in a safe way
     * @custom:then The pending action is removed
     * @custom:and The `to` address does not receive any assets or security deposit
     */
    function test_removeBlockedDepositSafe() public {
        uint256 balanceBefore = address(this).balance;
        uint256 assetBalanceBefore = wstETH.balanceOf(address(this));
        _removeBlockedVaultScenario(ProtocolAction.InitiateDeposit, 10 ether, false);
        assertEq(wstETH.balanceOf(address(this)), assetBalanceBefore, "asset balance after");
        assertEq(address(this).balance, balanceBefore, "balance after");
    }

    /**
     * @custom:scenario Remove a stuck withdrawal in an unsafe way
     * @custom:given A user has initiated a withdrawal which gets stuck for any reason
     * @custom:when The admin removes the pending action in an unsafe way
     * @custom:then The pending action is removed
     * @custom:and The `to` address receives the USDN and the security deposit
     */
    function test_removeBlockedWithdrawalUnsafe() public {
        uint256 balanceBefore = address(this).balance;
        uint256 usdnBalanceBefore = usdn.balanceOf(address(this));
        _removeBlockedVaultScenario(ProtocolAction.InitiateWithdrawal, 10 ether, true);
        assertEq(usdn.balanceOf(address(this)), usdnBalanceBefore + 20_000 ether, "usdn balance after");
        assertEq(address(this).balance, balanceBefore + protocol.getSecurityDepositValue(), "balance after");
    }

    /**
     * @custom:scenario Remove a stuck withdrawal in a safe way
     * @custom:given A user has initiated a withdrawal which gets stuck for any reason
     * @custom:when The admin removes the pending action in a safe way
     * @custom:then The pending action is removed
     * @custom:and The `to` address does not receive any USDN or security deposit
     */
    function test_removeBlockedWithdrawalSafe() public {
        uint256 balanceBefore = address(this).balance;
        uint256 usdnBalanceBefore = usdn.balanceOf(address(this));
        _removeBlockedVaultScenario(ProtocolAction.InitiateWithdrawal, 10 ether, false);
        assertEq(usdn.balanceOf(address(this)), usdnBalanceBefore, "usdn balance after");
        assertEq(address(this).balance, balanceBefore, "balance after");
    }

    /**
     * @notice Helper function to setup a long side pending action and remove it with the admin function
     * @param untilAction Whether to initiate an open or a close position
     * @param amount The amount of collateral
     * @param unsafe Whether to remove the action in an unsafe way
     */
    function _removeBlockedLongScenario(ProtocolAction untilAction, uint128 amount, bool unsafe)
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
        protocol.i_removeBlockedPendingAction(rawIndex, payable(address(this)), unsafe);

        assertTrue(protocol.getUserPendingAction(USER_1).action == ProtocolAction.None, "pending action");
        vm.expectRevert(DoubleEndedQueue.QueueOutOfBounds.selector);
        protocol.getQueueItem(rawIndex);

        (Position memory pos,) = protocol.getLongPosition(posId_);
        assertEq(pos.user, address(0), "pos user");
    }

    /**
     * @custom:scenario Remove a stuck open position in an unsafe way
     * @custom:given A user has initiated an open position which gets stuck for any reason
     * @custom:when The admin removes the pending action in an unsafe way
     * @custom:then The pending action is removed
     * @custom:and The protocol state is updated to remove the position
     */
    function test_removeBlockedOpenPositionUnsafe() public {
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
     * @custom:scenario Remove a stuck open position in a safe way
     * @custom:given A user has initiated an open position which gets stuck for any reason
     * @custom:when The admin removes the pending action in a safe way
     * @custom:then The pending action is removed
     * @custom:and The protocol state is not updated
     */
    function test_removeBlockedOpenPositionSafe() public {
        uint256 balanceBefore = address(this).balance;
        uint256 totalPosBefore = protocol.getTotalLongPositions();
        uint256 totalExpoBefore = protocol.getTotalExpo();

        _removeBlockedLongScenario(ProtocolAction.InitiateOpenPosition, 10 ether, false);

        assertEq(protocol.getTotalLongPositions(), totalPosBefore + 1, "total pos");
        assertGt(protocol.getTotalExpo(), totalExpoBefore, "total expo");

        assertEq(address(this).balance, balanceBefore, "balance after");
    }

    /**
     * @custom:scenario Remove a stuck close position in an unsafe way
     * @custom:given A user has initiated a close position which gets stuck for any reason
     * @custom:when The admin removes the pending action in an unsafe way
     * @custom:then The pending action is removed
     * @custom:and The protocol balances are updated to cleanup the position
     * @custom:and The `to` address receives the the security deposit
     */
    function test_removeBlockedClosePositionUnsafe() public {
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
     * @custom:scenario Remove a stuck close position in a safe way
     * @custom:given A user has initiated a close position which gets stuck for any reason
     * @custom:when The admin removes the pending action in a safe way
     * @custom:then The pending action is removed
     * @custom:and The protocol balances are not updated
     * @custom:and The `to` address does not receive any security deposit
     */
    function test_removeBlockedClosePositionSafe() public {
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

    function _wait() internal {
        _waitBeforeActionablePendingAction();
        skip(1 hours);
    }

    receive() external payable { }
}

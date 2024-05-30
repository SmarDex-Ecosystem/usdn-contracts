// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { UsdnProtocolBaseFixture } from "test/unit/UsdnProtocol/utils/Fixtures.sol";
import { ADMIN, USER_1 } from "test/utils/Constants.sol";

import { ProtocolAction } from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import { DoubleEndedQueue } from "src/libraries/DoubleEndedQueue.sol";

contract TestUsdnProtocolRemoveBlockedPendingAction is UsdnProtocolBaseFixture {
    function setUp() public {
        params = DEFAULT_PARAMS;
        params.flags.enableSecurityDeposit = true;
        super._setUp(params);
    }

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

    function test_removeBlockedDepositUnsafe() public {
        uint256 balanceBefore = address(this).balance;
        uint256 assetBalanceBefore = wstETH.balanceOf(address(this));
        _removeBlockedVaultScenario(ProtocolAction.InitiateDeposit, 10 ether, true);
        assertEq(wstETH.balanceOf(address(this)), assetBalanceBefore + 10 ether, "asset balance after");
        assertEq(address(this).balance, balanceBefore + protocol.getSecurityDepositValue(), "balance after");
    }

    function test_removeBlockedDepositSafe() public {
        uint256 balanceBefore = address(this).balance;
        uint256 assetBalanceBefore = wstETH.balanceOf(address(this));
        _removeBlockedVaultScenario(ProtocolAction.InitiateDeposit, 10 ether, false);
        assertEq(wstETH.balanceOf(address(this)), assetBalanceBefore, "asset balance after");
        assertEq(address(this).balance, balanceBefore, "balance after");
    }

    function test_removeBlockedWithdrawalUnsafe() public {
        uint256 balanceBefore = address(this).balance;
        uint256 usdnBalanceBefore = usdn.balanceOf(address(this));
        _removeBlockedVaultScenario(ProtocolAction.InitiateWithdrawal, 10 ether, true);
        assertEq(usdn.balanceOf(address(this)), usdnBalanceBefore + 20_000 ether, "usdn balance after");
        assertEq(address(this).balance, balanceBefore + protocol.getSecurityDepositValue(), "balance after");
    }

    function test_removeBlockedWithdrawalSafe() public {
        uint256 balanceBefore = address(this).balance;
        uint256 usdnBalanceBefore = usdn.balanceOf(address(this));
        _removeBlockedVaultScenario(ProtocolAction.InitiateWithdrawal, 10 ether, false);
        assertEq(usdn.balanceOf(address(this)), usdnBalanceBefore, "usdn balance after");
        assertEq(address(this).balance, balanceBefore, "balance after");
    }

    function _wait() internal {
        _waitBeforeActionablePendingAction();
        skip(1 hours);
    }

    receive() external payable { }
}

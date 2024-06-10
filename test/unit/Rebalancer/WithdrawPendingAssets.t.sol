// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { RebalancerFixture } from "test/unit/Rebalancer/utils/Fixtures.sol";
import { USER_1 } from "test/utils/Constants.sol";

/**
 * @custom:feature The `withdrawPendingAssets` function of the rebalancer contract
 * @custom:background Given a rebalancer contract
 */
contract TestRebalancerWithdrawPendingAssets is RebalancerFixture {
    uint128 constant INITIAL_DEPOSIT = 2 ether;

    function setUp() public {
        super._setUp();

        rebalancer.incrementPositionVersion();
        wstETH.mintAndApprove(address(this), 10_000 ether, address(rebalancer), type(uint256).max);

        assertGe(INITIAL_DEPOSIT, rebalancer.getMinAssetDeposit());
        rebalancer.depositAssets(INITIAL_DEPOSIT, address(this));
    }

    /**
     * @custom:scenario The user tries to withdraw assets to the zero address
     * @custom:given A user with deposited assets
     * @custom:when The user tries to withdraw assets with to as the zero address
     * @custom:then The call reverts with a RebalancerInvalidAddressTo error
     */
    function test_RevertWhen_withdrawPendingAssetsToTheZeroAddress() external {
        vm.expectRevert(RebalancerInvalidAddressTo.selector);
        rebalancer.withdrawPendingAssets(1, address(0));
    }

    /**
     * @custom:scenario The user tries to withdraw assets without having any deposit
     * @custom:given A user with no deposited assets
     * @custom:when The user tries to withdraw assets without having deposited first
     * @custom:then The call reverts with a RebalancerUserNotPending error
     */
    function test_RevertWhen_withdrawPendingAssetsWithNoDeposit() external {
        vm.expectRevert(RebalancerUserNotPending.selector);
        vm.prank(USER_1);
        rebalancer.withdrawPendingAssets(1, USER_1);
    }

    /**
     * @custom:scenario The user tries to withdraw assets after a position version change
     * @custom:given A user with deposited assets
     * @custom:when The position version gets incremented
     * @custom:and The user tries to withdraw assets
     * @custom:then The call reverts with a RebalancerUserNotPending error
     */
    function test_RevertWhen_withdrawPendingAssetsWithVersionChanged() external {
        rebalancer.incrementPositionVersion();

        vm.expectRevert(RebalancerUserNotPending.selector);
        rebalancer.withdrawPendingAssets(1, address(this));
    }

    /**
     * @custom:scenario The user tries to withdraw more assets than it has deposited
     * @custom:given A user with deposited assets
     * @custom:when The user tries to withdraw assets with an amount higher than what it deposited
     * @custom:then The call reverts with a RebalancerUserNotPending error
     */
    function test_RevertWhen_withdrawPendingAssetsWithAmountHigherThanAssetsDeposited() external {
        vm.expectRevert(RebalancerWithdrawAmountTooLarge.selector);
        rebalancer.withdrawPendingAssets(INITIAL_DEPOSIT + 1, address(this));
    }

    /**
     * @custom:scenario The user tries to withdraw assets with 0 as the amount
     * @custom:when withdrawPendingAssets is called with 0 as the amount
     * @custom:then The call reverts with a RebalancerInvalidAmount error
     */
    function test_RevertWhen_depositAssetsWithAmountZero() external {
        vm.expectRevert(RebalancerInvalidAmount.selector);
        rebalancer.withdrawPendingAssets(0, address(this));
    }

    /**
     * @custom:scenario The user withdraws its assets
     * @custom:given A user with deposited assets
     * @custom:when The user withdraws all its assets with another address as the 'to' address
     * @custom:then The 'to' address receives the expected amount
     * @custom:and the user's data in the contract is removed
     */
    function test_withdrawPendingAssets() external {
        uint256 rebalancerBalanceBefore = wstETH.balanceOf(address(rebalancer));
        uint256 userBalanceBefore = wstETH.balanceOf(USER_1);
        uint256 pendingAssetsBefore = rebalancer.getPendingAssetsAmount();

        vm.expectEmit();
        emit PendingAssetsWithdrawn(address(this), INITIAL_DEPOSIT, USER_1);
        rebalancer.withdrawPendingAssets(INITIAL_DEPOSIT, USER_1);

        assertEq(
            rebalancerBalanceBefore - INITIAL_DEPOSIT,
            wstETH.balanceOf(address(rebalancer)),
            "The rebalancer should have sent the assets"
        );
        assertEq(
            userBalanceBefore + INITIAL_DEPOSIT,
            wstETH.balanceOf(USER_1),
            "The to address should have received the assets"
        );

        // Check that the user is not in the contract anymore
        UserDeposit memory userDeposit = rebalancer.getUserDepositData(address(this));
        assertEq(userDeposit.entryPositionVersion, 0, "The position version should be back to 0");
        assertEq(userDeposit.amount, 0, "The amount should be 0");
        assertEq(
            rebalancer.getPendingAssetsAmount(),
            pendingAssetsBefore - INITIAL_DEPOSIT,
            "The amount withdrawn should have been subtracted from the pending assets"
        );
    }

    /**
     * @custom:scenario The user withdraws some of the assets it deposited
     * @custom:given A user with deposited assets
     * @custom:when The user withdraws its assets with an amount lower than the amount it deposited
     * @custom:then The user receives the expected amount
     */
    function test_withdrawPendingAssetsWithAmountLessThanDeposited() external {
        rebalancer.depositAssets(2 * INITIAL_DEPOSIT, address(this));
        uint128 totDeposit = INITIAL_DEPOSIT * 3;

        uint256 expectedPositionVersion = rebalancer.getPositionVersion() + 1;
        uint256 rebalancerBalanceBefore = wstETH.balanceOf(address(rebalancer));
        uint256 userBalanceBefore = wstETH.balanceOf(address(this));
        uint256 pendingAssetsBefore = rebalancer.getPendingAssetsAmount();
        uint128 amountToWithdraw = totDeposit * 6 / 10;

        vm.expectEmit();
        emit PendingAssetsWithdrawn(address(this), amountToWithdraw, address(this));
        rebalancer.withdrawPendingAssets(amountToWithdraw, address(this));

        assertEq(
            rebalancerBalanceBefore - amountToWithdraw,
            wstETH.balanceOf(address(rebalancer)),
            "The rebalancer should have sent the assets"
        );
        assertEq(
            userBalanceBefore + amountToWithdraw,
            wstETH.balanceOf(address(this)),
            "The user address should have received the assets"
        );

        UserDeposit memory userDeposit = rebalancer.getUserDepositData(address(this));
        assertEq(
            userDeposit.entryPositionVersion, expectedPositionVersion, "The position version should not have changed"
        );
        assertEq(userDeposit.amount, totDeposit * 4 / 10, "The amount withdrawn should have been subtracted");
        assertEq(
            rebalancer.getPendingAssetsAmount(),
            pendingAssetsBefore - amountToWithdraw,
            "The amount withdrawn should have been subtracted from the pending assets"
        );
    }

    /**
     * @custom:scenario The user withdraws some of the assets it deposited and leaves less than the minimum required
     * @custom:given A user with deposited assets
     * @custom:when The user withdraws its assets with an amount lower than the amount it deposited
     * @custom:then The transaction reverts with a RebalancerInsufficientAmount error
     */
    function test_RevertWhen_partialWithdraw_leftLessThanMin() external {
        vm.expectRevert(RebalancerInsufficientAmount.selector);
        rebalancer.withdrawPendingAssets(INITIAL_DEPOSIT / 2, address(this));
    }
}

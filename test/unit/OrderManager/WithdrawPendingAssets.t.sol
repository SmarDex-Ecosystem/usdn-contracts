// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { OrderManagerFixture } from "test/unit/OrderManager/utils/Fixtures.sol";
import { USER_1 } from "test/utils/Constants.sol";

/**
 * @custom:feature The withdrawPendingAssets function of the order manager contract
 * @custom:background Given an order manager contract
 */
contract TestOrderManagerWithdrawPendingAssets is OrderManagerFixture {
    function setUp() public {
        super._setUp();

        orderManager.incrementPositionVersion();
        wstETH.mintAndApprove(address(this), 10_000 ether, address(orderManager), type(uint256).max);
        orderManager.depositAssets(1 ether, address(this));
    }

    /**
     * @custom:scenario The user tries to withdraw assets to the zero address
     * @custom:given A user with deposited assets
     * @custom:when The user tries to withdraw assets with to as the zero address
     * @custom:then The call reverts with an OrderManagerInvalidAddressTo error
     */
    function test_RevertWhen_withdrawPendingAssetsToTheZeroAddress() external {
        vm.expectRevert(OrderManagerInvalidAddressTo.selector);
        orderManager.withdrawPendingAssets(1 ether, address(0));
    }

    /**
     * @custom:scenario The user tries to withdraw assets without having any deposited
     * @custom:given A user with no deposited assets
     * @custom:when The user tries to withdraw assets without having deposited first
     * @custom:then The call reverts with an OrderManagerUserNotPending error
     */
    function test_RevertWhen_withdrawPendingAssetsWithNoDeposit() external {
        vm.expectRevert(OrderManagerUserNotPending.selector);
        vm.prank(USER_1);
        orderManager.withdrawPendingAssets(1 ether, USER_1);
    }

    /**
     * @custom:scenario The user tries to withdraw assets after a position version change
     * @custom:given A user with deposited assets
     * @custom:when The position version gets incremented
     * @custom:and The user tries to withdraw assets
     * @custom:then The call reverts with an OrderManagerUserNotPending error
     */
    function test_RevertWhen_withdrawPendingAssetsWithVersionChanged() external {
        orderManager.incrementPositionVersion();

        vm.expectRevert(OrderManagerUserNotPending.selector);
        orderManager.withdrawPendingAssets(1 ether, address(this));
    }

    /**
     * @custom:scenario The user tries to withdraw more assets than it has deposited
     * @custom:given A user with deposited assets
     * @custom:when The user tries to withdraw assets with an amount higher than what it deposited
     * @custom:then The call reverts with an OrderManagerUserNotPending error
     */
    function test_RevertWhen_withdrawPendingAssetsWithAmountHigherThanAssetsDeposited() external {
        vm.expectRevert(OrderManagerWithdrawAmountTooLarge.selector);
        orderManager.withdrawPendingAssets(2 ether, address(this));
    }

    /**
     * @custom:scenario The user withdraw its assets
     * @custom:given A user with deposited assets
     * @custom:when The user withdraw all its assets with another address as the to address
     * @custom:then The to address receives the expected amount
     * @custom:and the user's data in the contract is removed
     */
    function test_withdrawPendingAssets() external {
        uint256 orderManagerBalanceBefore = wstETH.balanceOf(address(orderManager));
        uint256 userBalanceBefore = wstETH.balanceOf(USER_1);

        vm.expectEmit();
        emit PendingAssetsWithdrawn(address(this), 1 ether, USER_1);
        orderManager.withdrawPendingAssets(1 ether, USER_1);

        assertEq(
            orderManagerBalanceBefore - 1 ether,
            wstETH.balanceOf(address(orderManager)),
            "The order manager should have sent the assets"
        );
        assertEq(
            userBalanceBefore + 1 ether, wstETH.balanceOf(USER_1), "The to address should have received the assets"
        );

        // Check that the user is not in the contract anymore
        UserDeposit memory userDeposit = orderManager.getUserDepositData(address(this));
        assertEq(userDeposit.entryPositionVersion, 0, "The position version be back to 0");
        assertEq(userDeposit.amount, 0, "The amount should be 0");
    }

    /**
     * @custom:scenario The user withdraw some of the assets it deposited
     * @custom:given A user with deposited assets
     * @custom:when The user withdraw its assets with an amount lower than the amount it deposited
     * @custom:then The user receives the expected amount
     */
    function test_withdrawPendingAssetsWithAmountLessThanDeposited() external {
        uint256 positionVersion = orderManager.getCurrentPositionVersion();
        uint256 orderManagerBalanceBefore = wstETH.balanceOf(address(orderManager));
        uint256 userBalanceBefore = wstETH.balanceOf(address(this));

        vm.expectEmit();
        emit PendingAssetsWithdrawn(address(this), 0.6 ether, address(this));
        orderManager.withdrawPendingAssets(0.6 ether, address(this));

        assertEq(
            orderManagerBalanceBefore - 0.6 ether,
            wstETH.balanceOf(address(orderManager)),
            "The order manager should have sent the assets"
        );
        assertEq(
            userBalanceBefore + 0.6 ether,
            wstETH.balanceOf(address(this)),
            "The user address should have received the assets"
        );

        UserDeposit memory userDeposit = orderManager.getUserDepositData(address(this));
        assertEq(userDeposit.entryPositionVersion, positionVersion, "The position version should not have changed");
        assertEq(userDeposit.amount, 0.4 ether, "The amount withdrawn should have been subtracted");
    }
}

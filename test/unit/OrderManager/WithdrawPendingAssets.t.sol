// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { OrderManagerFixture } from "test/unit/OrderManager/utils/Fixtures.sol";
import { USER_1 } from "test/utils/Constants.sol";

/**
 * @custom:feature The withdrawPendingAssets function of the order manager contract
 * @custom:background Given a protocol instance that was initialized with default params
 * @custom:and an order manager contract
 */
contract TestOrderManagerWithdrawPendingAssets is OrderManagerFixture {
    function setUp() public {
        super._setUp();

        wstETH.mintAndApprove(address(this), 10_000 ether, address(orderManager), type(uint256).max);
        orderManager.depositAssets(1 ether, address(this));
    }

    /**
     * @custom:scenario The user tries to withdraw assets to the zero address
     * @custom:given A user with deposited assets
     * @custom:when The user tries to withdraw funds with to as the zero address
     * @custom:then The call reverts with an OrderManagerInvalidAddressTo error
     */
    function test_RevertWhen_withdrawPendingAssetsToTheZeroAddress() external {
        vm.expectRevert(OrderManagerInvalidAddressTo.selector);
        orderManager.withdrawPendingAssets(1 ether, address(0));
    }

    /**
     * @custom:scenario The user tries to withdraw assets without having any deposited
     * @custom:given A user with no deposited assets
     * @custom:when The user tries to withdraw funds without having deposited first
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
     * @custom:and The user tries to withdraw funds
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
        vm.expectRevert(OrderManagerNotEnoughAssetsToWithdraw.selector);
        orderManager.withdrawPendingAssets(2 ether, address(this));
    }

    /**
     * @custom:scenario The user withdraw its assets
     * @custom:given A user with deposited assets
     * @custom:when The user withdraw its assets with another address as the to address
     * @custom:then The user receives its assets
     */
    function test_withdrawPendingAssets() external {
        uint256 orderManagerBalanceBefore = wstETH.balanceOf(address(orderManager));
        uint256 userBalanceBefore = wstETH.balanceOf(USER_1);

        vm.expectEmit();
        emit PendingAssetsWithdrawn(1 ether, USER_1);
        orderManager.withdrawPendingAssets(1 ether, USER_1);

        assertEq(
            orderManagerBalanceBefore - 1 ether,
            wstETH.balanceOf(address(orderManager)),
            "The order manager should have sent the assets"
        );
        assertEq(
            userBalanceBefore + 1 ether, wstETH.balanceOf(USER_1), "The to address should have received the assets"
        );

        UserDeposit memory userDeposit = orderManager.getUserDepositData(address(this));
        assertEq(userDeposit.entryPositionVersion, 0);
        assertEq(userDeposit.amount, 0);
    }

    /**
     * @custom:scenario The user withdraw some of the assets it deposited
     * @custom:given A user with deposited assets
     * @custom:when The user withdraw its assets with an amount lower than the amount it deposited
     * @custom:then The user receives the expected amount
     */
    function test_withdrawPendingAssetsWithAmountLessThanDeposited() external {
        uint256 orderManagerBalanceBefore = wstETH.balanceOf(address(orderManager));
        uint256 userBalanceBefore = wstETH.balanceOf(address(this));

        vm.expectEmit();
        emit PendingAssetsWithdrawn(0.6 ether, address(this));
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
        assertEq(userDeposit.entryPositionVersion, 0);
        assertEq(userDeposit.amount, 0.4 ether);
    }
}

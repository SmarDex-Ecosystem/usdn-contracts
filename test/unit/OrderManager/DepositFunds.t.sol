// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { OrderManagerFixture } from "test/unit/OrderManager/utils/Fixtures.sol";

/**
 * @custom:feature The depositAssets function of the order manager contract
 * @custom:background Given an order manager contract
 */
contract TestOrderManagerDepositAssets is OrderManagerFixture {
    function setUp() public {
        super._setUp();

        wstETH.mintAndApprove(address(this), 10_000 ether, address(orderManager), type(uint256).max);
    }

    /**
     * @custom:scenario The user tries to deposit more assets after the position version has changed
     * @custom:given A user that deposited assets in the contract
     * @custom:when The position version is incremented
     * @custom:and The user tries to deposit more assets
     * @custom:then The call reverts with a OrderManagerUserNotPending error
     */
    function test_RevertWhen_depositAssetsAfterVersionChanged() external {
        orderManager.depositAssets(1 ether, address(this));
        orderManager.incrementPositionVersion();

        vm.expectRevert(OrderManagerUserNotPending.selector);
        orderManager.depositAssets(1 ether, address(this));
    }

    /**
     * @custom:scenario The user tries to deposit assets with to as the zero address
     * @custom:given A user with assets
     * @custom:when The user tries to deposit assets with to as the zero address
     * @custom:then The call reverts with a OrderManagerInvalidAddressTo error
     */
    function test_RevertWhen_depositAssetsToTheZeroAddress() external {
        vm.expectRevert(OrderManagerInvalidAddressTo.selector);
        orderManager.depositAssets(1 ether, address(0));
    }

    /**
     * @custom:scenario The user deposit assets
     * @custom:given A user with assets
     * @custom:when The user deposit assets with his address as the to address
     * @custom:then His assets are transferred to the contract
     */
    function test_depositAssets() external {
        uint128 expectedPositionVersion = orderManager.getPositionVersion() + 1;
        uint256 orderManagerBalanceBefore = wstETH.balanceOf(address(orderManager));
        uint256 userBalanceBefore = wstETH.balanceOf(address(this));

        vm.expectEmit();
        emit AssetsDeposited(1 ether, address(this), expectedPositionVersion);
        orderManager.depositAssets(1 ether, address(this));

        assertEq(
            orderManagerBalanceBefore + 1 ether,
            wstETH.balanceOf(address(orderManager)),
            "The order manager should have received the assets"
        );
        assertEq(userBalanceBefore - 1 ether, wstETH.balanceOf(address(this)), "The user should have sent the assets");

        UserDeposit memory userDeposit = orderManager.getUserDepositData(address(this));
        assertEq(
            userDeposit.entryPositionVersion, expectedPositionVersion, "The position version should be the expected one"
        );
        assertEq(userDeposit.amount, 1 ether, "The amount should have been saved");
    }

    /**
     * @custom:scenario The user deposit assets again
     * @custom:given A user with assets already deposited
     * @custom:when The user deposit assets again with his address as the to address
     * @custom:then His assets are transferred to the contract
     * @custom:and the sum of deposits is saved
     */
    function test_depositAssetsTwice() external {
        uint128 expectedPositionVersion = orderManager.getPositionVersion() + 1;
        uint128 firstDepositAmount = 1 ether;
        orderManager.depositAssets(firstDepositAmount, address(this));

        uint128 secondDepositAmount = 0.5 ether;
        uint256 orderManagerBalanceBefore = wstETH.balanceOf(address(orderManager));
        uint256 userBalanceBefore = wstETH.balanceOf(address(this));
        vm.expectEmit();
        emit AssetsDeposited(secondDepositAmount, address(this), expectedPositionVersion);
        orderManager.depositAssets(secondDepositAmount, address(this));

        assertEq(
            orderManagerBalanceBefore + secondDepositAmount,
            wstETH.balanceOf(address(orderManager)),
            "The order manager should have received the assets"
        );
        assertEq(
            userBalanceBefore - secondDepositAmount,
            wstETH.balanceOf(address(this)),
            "The user should have sent the assets"
        );

        UserDeposit memory userDeposit = orderManager.getUserDepositData(address(this));
        assertEq(
            userDeposit.entryPositionVersion, expectedPositionVersion, "The position version should be the expected one"
        );
        assertEq(
            userDeposit.amount, firstDepositAmount + secondDepositAmount, "The sum of amounts should have been saved"
        );
    }
}

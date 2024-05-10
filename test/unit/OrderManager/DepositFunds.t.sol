// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { OrderManagerFixture } from "test/unit/OrderManager/utils/Fixtures.sol";

/**
 * @custom:feature The depositAssets function of the order manager contract
 * @custom:background Given a protocol instance that was initialized with default params
 * @custom:and an order manager contract
 */
contract TestOrderManagerDepositAssets is OrderManagerFixture {
    function setUp() public {
        super._setUp();

        wstETH.mintAndApprove(address(this), 10_000 ether, address(orderManager), type(uint256).max);
    }

    /**
     * @custom:scenario The user tries to deposit more funds after the position version has changed
     * @custom:given A user that deposited funds in the contract
     * @custom:when The position version is incremented
     * @custom:and The user tries to deposit more funds
     * @custom:then The call reverts with a OrderManagerUserNotPending error
     */
    function test_RevertWhen_depositAssetsAfterVersionChanged() external {
        orderManager.depositAssets(1 ether, address(this));
        orderManager.incrementPositionVersion();

        vm.expectRevert(OrderManagerUserNotPending.selector);
        orderManager.depositAssets(1 ether, address(this));
    }

    /**
     * @custom:scenario The user tries to deposit funds to the zero address
     * @custom:given A user with assets
     * @custom:when The user tries to deposit funds with to as the zero address
     * @custom:then The call reverts with a OrderManagerInvalidAddressTo error
     */
    function test_RevertWhen_depositAssetsToTheZeroAddress() external {
        vm.expectRevert(OrderManagerInvalidAddressTo.selector);
        orderManager.depositAssets(1 ether, address(0));
    }

    /**
     * @custom:scenario The user deposit funds
     * @custom:given A user with assets
     * @custom:when The user deposit funds with his address as the to address
     * @custom:then His assets are transferred to the contract
     */
    function test_depositAssets() external {
        uint256 orderManagerBalanceBefore = wstETH.balanceOf(address(orderManager));
        uint256 userBalanceBefore = wstETH.balanceOf(address(this));

        vm.expectEmit();
        emit AssetsDeposited(1 ether, address(this), 0);
        orderManager.depositAssets(1 ether, address(this));

        assertEq(
            orderManagerBalanceBefore + 1 ether,
            wstETH.balanceOf(address(orderManager)),
            "The order manager should have receive the assets"
        );
        assertEq(userBalanceBefore - 1 ether, wstETH.balanceOf(address(this)), "The user should have sent the assets");

        UserDeposit memory userDeposit = orderManager.getUserDepositData(address(this));
        assertEq(userDeposit.entryPositionVersion, orderManager.getCurrentPositionVersion());
        assertEq(userDeposit.amount, 1 ether);
    }
}

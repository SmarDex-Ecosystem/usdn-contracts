// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { IOrderManager } from "src/interfaces/OrderManager/IOrderManager.sol";
import { IOrderManagerErrors } from "src/interfaces/OrderManager/IOrderManagerErrors.sol";
import { IOrderManagerEvents } from "src/interfaces/OrderManager/IOrderManagerEvents.sol";

import { USER_1 } from "test/utils/Constants.sol";
import { UsdnProtocolBaseFixture } from "test/unit/UsdnProtocol/utils/Fixtures.sol";

/**
 * @custom:feature Test the withdrawAssetsFromTick function of the OrderManager contract
 * @custom:background Given a protocol initialized with default params
 * @custom:and 1 wstETH in the test contract
 * @custom:and 2 wstETH in the test USER_1 address
 * @custom:and a 1 ether order at the 2000$ tick
 */
contract TestOrderManagerWithdrawAssetsFromTick is UsdnProtocolBaseFixture, IOrderManagerErrors, IOrderManagerEvents {
    int24 private _tick;
    uint232 private _amount;

    function setUp() public {
        _setUp(DEFAULT_PARAMS);

        _tick = protocol.getEffectiveTickForPrice(2000 ether);
        _amount = 1 ether;

        wstETH.mintAndApprove(address(this), _amount, address(orderManager), type(uint256).max);
        wstETH.mintAndApprove(USER_1, _amount + 1 ether, address(orderManager), type(uint256).max);
        orderManager.depositAssetsInTick(_tick, _amount);
    }

    /* -------------------------------------------------------------------------- */
    /*                                   Reverts                                  */
    /* -------------------------------------------------------------------------- */

    /**
     * @custom:scenario withdrawAssetsFromTick is called but there are no order for the user in the tick
     * @custom:given A tick with orders but none for the user
     * @custom:when withdrawAssetsFromTick is called for this tick
     * @custom:then the call reverts with a OrderManagerInsufficientFunds error
     */
    function test_RevertWhen_noTickForTheCurrentUser() external {
        vm.prank(USER_1);
        vm.expectRevert(abi.encodeWithSelector(OrderManagerInsufficientFunds.selector, _tick, USER_1, 0, _amount));
        orderManager.withdrawAssetsFromTick(_tick, _amount);
    }

    /* -------------------------------------------------------------------------- */
    /*                           withdrawAssetsFromTick                           */
    /* -------------------------------------------------------------------------- */

    /**
     * @custom:scenario A user wants to withdraw their assets from a tick
     * @custom:given A tick with an order from the user
     * @custom:when withdrawAssetsFromTick is called for this tick with te full amount
     * @custom:then the assets are removed from the tick
     * @custom:and an UserWithdrewAssetsFromTick event is emitted
     * @custom:and the assets are sent back to the user
     * @custom:and the state of the order manager is updated
     */
    function test_withdrawAssetsFromTick() external {
        uint256 orderManagerBalanceBefore = wstETH.balanceOf(address(orderManager));
        uint256 userBalanceBefore = wstETH.balanceOf(address(this));

        vm.expectEmit();
        emit UserWithdrewAssetsFromTick(address(this), 0, _tick, 0);
        orderManager.withdrawAssetsFromTick(_tick, _amount);

        assertEq(
            orderManagerBalanceBefore - _amount,
            wstETH.balanceOf(address(orderManager)),
            "The assets should have been taken out of the order manager"
        );
        assertEq(
            userBalanceBefore + _amount, wstETH.balanceOf(address(this)), "The assets should have been sent to the user"
        );

        IOrderManager.OrdersDataInTick memory ordersData = orderManager.getOrdersDataInTick(_tick, 0);
        assertEq(ordersData.amountOfAssets, 0, "The accumulated amount should be equal to 0");
        assertEq(
            ordersData.longPositionTick,
            orderManager.PENDING_ORDERS_TICK(),
            "The tick should be equal to the PENDING_ORDERS_TICK constant"
        );
        assertEq(ordersData.longPositionTickVersion, 0, "The tick version should be 0");
        assertEq(ordersData.longPositionIndex, 0, "Index of the position should be 0");

        uint256 userOrderAmount = orderManager.getUserAmountInTick(_tick, 0, address(this));
        assertEq(userOrderAmount, 0, "The user should have no assets left on the tick");
    }

    /**
     * @custom:scenario A user wants to remove their order from a tick partially
     * @custom:given A tick with an order from the user
     * @custom:when withdrawAssetsFromTick is called for this tick with an amount lower than the amount in the tick
     * @custom:then the amount of the user in the tick is removed from the contract
     * @custom:and an UserWithdrewAssetsFromTick event is emitted
     * @custom:and the assets are sent back to the user
     * @custom:and the state of the order manager is updated
     */
    function test_withdrawAssetsFromTickPartially() external {
        uint256 orderManagerBalanceBefore = wstETH.balanceOf(address(orderManager));
        uint256 userBalanceBefore = wstETH.balanceOf(address(this));
        uint232 partialAmount = _amount / 3;
        uint232 amountLeft = _amount - partialAmount;

        /* ----------------- 1st call that withdraw a partial amount ---------------- */
        vm.expectEmit();
        emit UserWithdrewAssetsFromTick(address(this), amountLeft, _tick, 0);
        orderManager.withdrawAssetsFromTick(_tick, partialAmount);

        assertEq(
            orderManagerBalanceBefore - partialAmount,
            wstETH.balanceOf(address(orderManager)),
            "The partial amount should have been taken out of the order manager"
        );
        assertEq(
            userBalanceBefore + partialAmount,
            wstETH.balanceOf(address(this)),
            "The partial amount should have been sent to the user"
        );

        IOrderManager.OrdersDataInTick memory ordersData = orderManager.getOrdersDataInTick(_tick, 0);
        assertEq(
            ordersData.amountOfAssets,
            amountLeft,
            "The partial amount should have been subtracted from the accumulated amount"
        );

        uint256 userOrderAmount = orderManager.getUserAmountInTick(_tick, 0, address(this));
        assertEq(userOrderAmount, amountLeft, "The user should have assets left on the tick");

        /* -------------- 2nd call that withdraw the rest of the assets ------------- */
        orderManagerBalanceBefore = wstETH.balanceOf(address(orderManager));
        userBalanceBefore = wstETH.balanceOf(address(this));

        vm.expectEmit();
        emit UserWithdrewAssetsFromTick(address(this), 0, _tick, 0);
        orderManager.withdrawAssetsFromTick(_tick, amountLeft);

        assertEq(
            orderManagerBalanceBefore - amountLeft,
            wstETH.balanceOf(address(orderManager)),
            "The assets should have been taken out of the order manager"
        );
        assertEq(
            userBalanceBefore + amountLeft,
            wstETH.balanceOf(address(this)),
            "The assets should have been sent to the user"
        );

        ordersData = orderManager.getOrdersDataInTick(_tick, 0);
        assertEq(ordersData.amountOfAssets, 0, "The accumulated amount should be equal to 0");

        userOrderAmount = orderManager.getUserAmountInTick(_tick, 0, address(this));
        assertEq(userOrderAmount, 0, "The user should have no assets left on the tick");
    }
}

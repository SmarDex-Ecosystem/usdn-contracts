// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { IOrderManager } from "src/interfaces/OrderManager/IOrderManager.sol";
import { IOrderManagerErrors } from "src/interfaces/OrderManager/IOrderManagerErrors.sol";
import { IOrderManagerEvents } from "src/interfaces/OrderManager/IOrderManagerEvents.sol";

import { USER_1 } from "test/utils/Constants.sol";
import { UsdnProtocolBaseFixture } from "test/unit/UsdnProtocol/utils/Fixtures.sol";

/**
 * @custom:feature Test the removeOrderFromTick function of the OrderManager contract
 * @custom:background Given a protocol initialized with default params
 * @custom:and 100 wstETH in the test contract
 * @custom:and a 1 ether order at the 2000$ tick
 */
contract TestOrderManagerRemoveOrderFromTick is UsdnProtocolBaseFixture, IOrderManagerErrors, IOrderManagerEvents {
    int24 private _tick;
    uint96 private _amount;

    function setUp() public {
        _setUp(DEFAULT_PARAMS);

        _tick = protocol.getEffectiveTickForPrice(2000 ether);
        _amount = 1 ether;

        wstETH.mintAndApprove(address(this), _amount, address(orderManager), type(uint256).max);
        wstETH.mintAndApprove(USER_1, _amount + 1 ether, address(orderManager), type(uint256).max);
        orderManager.addOrderInTick(_tick, _amount);
    }

    /* -------------------------------------------------------------------------- */
    /*                                   Reverts                                  */
    /* -------------------------------------------------------------------------- */

    /**
     * @custom:scenario removeOrderFromTick is called but there are no order for the user in the tick
     * @custom:given A tick with orders but none for the user
     * @custom:when removeOrderFromTick is called for this tick
     * @custom:then the call reverts with a OrderManagerNoOrderForUserInTick error
     */
    function test_RervertsWhen_noTickForTheCurrentUser() external {
        vm.prank(USER_1);
        vm.expectRevert(abi.encodeWithSelector(OrderManagerNoOrderForUserInTick.selector, _tick, USER_1));
        orderManager.removeOrderFromTick(_tick);
    }

    /* -------------------------------------------------------------------------- */
    /*                             removeOrderFromTick                            */
    /* -------------------------------------------------------------------------- */

    /**
     * @custom:scenario A user wants to remove his order from a tick
     * @custom:given A tick with an order from the user
     * @custom:when removeOrderFromTick is called for this tick
     * @custom:then the order is removed from the order array in the tick
     * @custom:and an OrderRemoved event is emitted
     * @custom:and the assets are sent back to the user
     * @custom:and the state of the order manager is updated
     */
    function test_removeOrderFromTick() external {
        uint256 orderManagerBalanceBefore = wstETH.balanceOf(address(orderManager));
        uint256 userBalanceBefore = wstETH.balanceOf(address(this));

        vm.expectEmit();
        emit OrderRemoved(address(this), _tick, 0);
        orderManager.removeOrderFromTick(_tick);

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
        assertEq(ordersData.longPositionTickVersion, 0, "The tick version shoudl be 0");
        assertEq(ordersData.longPositionIndex, 0, "Index of the position should be 0");

        uint232 userOrderAmount = orderManager.getUserAmountInTick(_tick, 0, address(this));
        assertEq(userOrderAmount, 0, "The user should have no assets left on the tick");
    }
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { IOrderManager } from "src/interfaces/OrderManager/IOrderManager.sol";
import { IOrderManagerErrors } from "src/interfaces/OrderManager/IOrderManagerErrors.sol";
import { IOrderManagerEvents } from "src/interfaces/OrderManager/IOrderManagerEvents.sol";
import { TickMath } from "src/libraries/TickMath.sol";

import { USER_1 } from "test/utils/Constants.sol";
import { UsdnProtocolBaseFixture } from "test/unit/UsdnProtocol/utils/Fixtures.sol";

/**
 * @custom:feature Test the depositAssetsInTick function of the OrderManager contract
 * @custom:background Given a protocol initialized with default params
 * @custom:and 100 wstETH in the test contract
 * @custom:and 100 wstETH in the USER_1 address
 */
contract TestOrderManagerDepositAssetsInTick is UsdnProtocolBaseFixture, IOrderManagerErrors, IOrderManagerEvents {
    function setUp() public {
        _setUp(DEFAULT_PARAMS);

        wstETH.mintAndApprove(address(this), 100 ether, address(orderManager), type(uint256).max);
        wstETH.mintAndApprove(USER_1, 100 ether, address(orderManager), type(uint256).max);
    }

    /* -------------------------------------------------------------------------- */
    /*                                   Reverts                                  */
    /* -------------------------------------------------------------------------- */

    /**
     * @custom:scenario depositAssetsInTick is called with a tick not respecting the tick spacing
     * @custom:given A tick that is not a multiple of the tick spacing
     * @custom:when depositAssetsInTick is called
     * @custom:then the call reverts with a OrderManagerInvalidTick error
     */
    function test_RevertWhen_tickDoesNotMatchTickSpacing() external {
        int24 tick = protocol.getEffectiveTickForPrice(2000 ether) + 1;

        vm.expectRevert(abi.encodeWithSelector(OrderManagerInvalidTick.selector, tick));
        orderManager.depositAssetsInTick(tick, 1 ether);
    }

    /**
     * @custom:scenario depositAssetsInTick is called with a tick lower than the min usable tick
     * @custom:given A tick lower than the min usable tick
     * @custom:when depositAssetsInTick is called
     * @custom:then the call reverts with a OrderManagerInvalidTick error
     */
    function test_RevertWhen_tickIsLowerThanMinTick() external {
        int24 tickSpacing = protocol.getTickSpacing();
        int24 tick = TickMath.minUsableTick(tickSpacing) - tickSpacing;

        vm.expectRevert(abi.encodeWithSelector(OrderManagerInvalidTick.selector, tick));
        orderManager.depositAssetsInTick(tick, 1 ether);
    }

    /**
     * @custom:scenario depositAssetsInTick is called with a tick higher than the max usable tick
     * @custom:given A tick higher than the max usable tick
     * @custom:when depositAssetsInTick is called
     * @custom:then the call reverts with a OrderManagerInvalidTick error
     */
    function test_RevertWhen_tickIsHigherThanMaxTick() external {
        int24 tickSpacing = protocol.getTickSpacing();
        int24 tick = TickMath.maxUsableTick(tickSpacing) + tickSpacing;

        vm.expectRevert(abi.encodeWithSelector(OrderManagerInvalidTick.selector, tick));
        orderManager.depositAssetsInTick(tick, 1 ether);
    }

    /* -------------------------------------------------------------------------- */
    /*                             depositAssetsInTick                            */
    /* -------------------------------------------------------------------------- */

    /**
     * @custom:scenario A user deposits assets in a tick
     * @custom:given A user with a 1 ether balance
     * @custom:when That user calls depositAssetsInTick
     * @custom:then The order is created
     * @custom:and an UserDepositedAssetsInTick event is emitted
     * @custom:and the funds are transferred from the user to the contract
     * @custom:and the state of the contract is updated
     */
    function test_depositAssetsInTick() external {
        int24 tick = protocol.getEffectiveTickForPrice(2000 ether);
        uint256 tickVersion = 0;
        uint96 amount = 1 ether;
        uint256 orderManagerBalanceBefore = wstETH.balanceOf(address(orderManager));
        uint256 userBalanceBefore = wstETH.balanceOf(address(this));

        vm.expectEmit();
        emit UserDepositedAssetsInTick(address(this), amount, tick, tickVersion);
        orderManager.depositAssetsInTick(tick, amount);

        assertEq(
            orderManagerBalanceBefore + amount,
            wstETH.balanceOf(address(orderManager)),
            "The assets were not sent to the order manager"
        );
        assertEq(userBalanceBefore - amount, wstETH.balanceOf(address(this)), "The assets were not taken from the user");

        uint232 userOrderAmount = orderManager.getUserAmountInTick(tick, tickVersion, address(this));
        assertEq(userOrderAmount, amount, "Wrong amount of assets saved for the user");

        IOrderManager.OrdersDataInTick memory ordersData = orderManager.getOrdersDataInTick(tick, tickVersion);
        assertEq(ordersData.amountOfAssets, amount, "The accumulated amount should be equal to the amount of the order");
        assertEq(
            ordersData.longPositionTick,
            orderManager.PENDING_ORDERS_TICK(),
            "The tick should be equal to the PENDING_ORDERS_TICK constant"
        );
        assertEq(ordersData.longPositionTickVersion, 0, "The tick version should be 0");
        assertEq(ordersData.longPositionIndex, 0, "Index of the position should be 0");
    }

    /**
     * @custom:scenario A user deposits assets 2 times in the same tick
     * @custom:given A user with a 1 ether balance
     * @custom:when That user calls depositAssetsInTick 2 times on the same tick
     * @custom:then The amount of funds in the tick is equal to the sum of amounts in both calls
     * @custom:and 2 UserDepositedAssetsInTick events are emitted
     * @custom:and the funds are transferred from the user to the contract
     * @custom:and the state of the contract is updated
     */
    function test_depositAssetsMultipleTimesInTheSameTick() external {
        int24 tick = protocol.getEffectiveTickForPrice(2000 ether);
        uint256 tickVersion = 0;
        uint96 amount = 0.5 ether;
        uint256 orderManagerBalanceBefore = wstETH.balanceOf(address(orderManager));
        uint256 userBalanceBefore = wstETH.balanceOf(address(this));

        /* -------------------------------- 1st call -------------------------------- */

        vm.expectEmit();
        emit UserDepositedAssetsInTick(address(this), amount, tick, tickVersion);
        orderManager.depositAssetsInTick(tick, amount);

        uint232 userOrderAmount = orderManager.getUserAmountInTick(tick, tickVersion, address(this));
        assertEq(userOrderAmount, amount, "Wrong amount of assets saved for the user");
        assertEq(userBalanceBefore - amount, wstETH.balanceOf(address(this)), "The assets were not taken from the user");

        IOrderManager.OrdersDataInTick memory ordersData = orderManager.getOrdersDataInTick(tick, tickVersion);
        assertEq(ordersData.amountOfAssets, amount, "The accumulated amount should be equal to the amount of the order");
        assertEq(
            orderManagerBalanceBefore + amount,
            wstETH.balanceOf(address(orderManager)),
            "The assets were not sent to the order manager"
        );

        /* -------------------------------- 2nd call -------------------------------- */
        orderManagerBalanceBefore = wstETH.balanceOf(address(orderManager));
        userBalanceBefore = wstETH.balanceOf(address(this));

        vm.expectEmit();
        emit UserDepositedAssetsInTick(address(this), amount * 2, tick, tickVersion);
        orderManager.depositAssetsInTick(tick, amount);

        userOrderAmount = orderManager.getUserAmountInTick(tick, tickVersion, address(this));
        assertEq(
            userOrderAmount,
            amount * 2,
            "The amount of assets saved for the user should be the sum of the amount in the tick"
        );
        assertEq(
            userBalanceBefore - amount,
            wstETH.balanceOf(address(this)),
            "The assets were not taken from the user on the 2nd call"
        );

        ordersData = orderManager.getOrdersDataInTick(tick, tickVersion);
        assertEq(ordersData.amountOfAssets, amount * 2, "The accumulated amount should be equal to the sum of amounts");
        assertEq(
            orderManagerBalanceBefore + amount,
            wstETH.balanceOf(address(orderManager)),
            "The assets were not sent to the order manager on the 2nd call"
        );
    }

    /**
     * @custom:scenario 2 users deposit assets in the same tick
     * @custom:given 2 users with a balance of at least 1 ether
     * @custom:when Those users call depositAssetsInTick wit te same tick
     * @custom:then The orders are created
     * @custom:and UserDepositedAssetsInTick events are emitted
     * @custom:and the funds are transferred from the users to the contract
     * @custom:and the state of the contract is updated
     */
    function test_depositAssetsInTheSameTickFromDifferentUsers() external {
        int24 tick = protocol.getEffectiveTickForPrice(2000 ether);
        uint256 tickVersion = 0;
        uint96 amountUser1 = 1 ether;
        uint96 amountUser2 = 2 ether;
        uint256 orderManagerBalanceBefore = wstETH.balanceOf(address(orderManager));
        uint256 userBalanceBefore = wstETH.balanceOf(address(this));

        vm.expectEmit();
        emit UserDepositedAssetsInTick(address(this), amountUser1, tick, tickVersion);
        orderManager.depositAssetsInTick(tick, amountUser1);

        assertEq(
            orderManagerBalanceBefore + amountUser1,
            wstETH.balanceOf(address(orderManager)),
            "The assets were not sent to the order manager"
        );
        assertEq(
            userBalanceBefore - amountUser1, wstETH.balanceOf(address(this)), "The assets were not taken from the user"
        );

        uint232 userOrderAmount = orderManager.getUserAmountInTick(tick, tickVersion, address(this));
        assertEq(userOrderAmount, amountUser1, "Wrong amount of assets saved for the user");

        IOrderManager.OrdersDataInTick memory ordersData = orderManager.getOrdersDataInTick(tick, tickVersion);
        assertEq(
            ordersData.amountOfAssets,
            amountUser1,
            "The accumulated amount should be equal to the amount of the only order"
        );
        assertEq(
            ordersData.longPositionTick,
            orderManager.PENDING_ORDERS_TICK(),
            "The tick should be equal to the PENDING_ORDERS_TICK constant"
        );
        assertEq(ordersData.longPositionTickVersion, 0, "The tick version should be 0");
        assertEq(ordersData.longPositionIndex, 0, "Index of the position should be 0");

        /* ------------------------- Order of the other user ------------------------ */
        vm.prank(USER_1);
        vm.expectEmit();
        emit UserDepositedAssetsInTick(USER_1, amountUser2, tick, tickVersion);
        orderManager.depositAssetsInTick(tick, amountUser2);

        userOrderAmount = orderManager.getUserAmountInTick(tick, tickVersion, address(this));
        assertEq(userOrderAmount, amountUser1, "The amount of assets for the first user should not have changed");
        userOrderAmount = orderManager.getUserAmountInTick(tick, tickVersion, USER_1);
        assertEq(userOrderAmount, amountUser2, "Wrong amount of assets saved for the user");

        ordersData = orderManager.getOrdersDataInTick(tick, tickVersion);
        assertEq(
            ordersData.amountOfAssets,
            amountUser1 + amountUser2,
            "The accumulated amount of assets should be the sum of all the added amounts of funds"
        );
    }
}

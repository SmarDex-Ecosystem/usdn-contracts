// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { IOrderManager } from "src/interfaces/OrderManager/IOrderManager.sol";
import { IOrderManagerErrors } from "src/interfaces/OrderManager/IOrderManagerErrors.sol";
import { IOrderManagerEvents } from "src/interfaces/OrderManager/IOrderManagerEvents.sol";
import { TickMath } from "src/libraries/TickMath.sol";
import { OrderManager } from "src/OrderManager.sol";

import { USER_1 } from "test/utils/Constants.sol";
import { UsdnProtocolBaseFixture } from "test/unit/UsdnProtocol/utils/Fixtures.sol";

/**
 * @custom:feature Test the addOrderInTick function of the OrderManager contract
 * @custom:background Given a protocol initialized with default params
 * @custom:and 100 wstETH in the test contract
 */
contract TestOrderManagerAddOrderInTick is UsdnProtocolBaseFixture, IOrderManagerErrors, IOrderManagerEvents {
    function setUp() public {
        _setUp(DEFAULT_PARAMS);

        wstETH.mintAndApprove(address(this), 100 ether, address(orderManager), type(uint256).max);
        wstETH.mintAndApprove(USER_1, 100 ether, address(orderManager), type(uint256).max);
    }

    /* -------------------------------------------------------------------------- */
    /*                                   Reverts                                  */
    /* -------------------------------------------------------------------------- */

    /**
     * @custom:scenario addOrderInTick is called although the order manager contract hasn't been initialized
     * @custom:given A non-initialized order manager contract
     * @custom:when addOrderInTick is called
     * @custom:then the call reverts with a OrderManagerNotInitialized error
     */
    function test_RervertsWhen_orderManagerNotInitialized() external {
        // Create a new instance of the protocol that is not initialized
        orderManager = new OrderManager();
        int24 tick = protocol.getEffectiveTickForPrice(2000 ether);

        vm.expectRevert(abi.encodeWithSelector(OrderManagerNotInitialized.selector));
        orderManager.addOrderInTick(tick, 1 ether);
    }

    /**
     * @custom:scenario addOrderInTick is called with a tick not respecting the tick spacing
     * @custom:given A tick that is not a multiple of the tick spacing
     * @custom:when addOrderInTick is called
     * @custom:then the call reverts with a OrderManagerInvalidTick error
     */
    function test_RervertsWhen_tickDoesNotMatchTickSpacing() external {
        int24 tick = protocol.getEffectiveTickForPrice(2000 ether) + 1;

        vm.expectRevert(abi.encodeWithSelector(OrderManagerInvalidTick.selector, tick));
        orderManager.addOrderInTick(tick, 1 ether);
    }

    /**
     * @custom:scenario addOrderInTick is called with a tick lower than the min usable tick
     * @custom:given A tick lower than the min usable tick
     * @custom:when addOrderInTick is called
     * @custom:then the call reverts with a OrderManagerInvalidTick error
     */
    function test_RervertsWhen_tickIsLowerThanMinTick() external {
        int24 tickSpacing = protocol.getTickSpacing();
        int24 tick = TickMath.minUsableTick(tickSpacing) - tickSpacing;

        vm.expectRevert(abi.encodeWithSelector(OrderManagerInvalidTick.selector, tick));
        orderManager.addOrderInTick(tick, 1 ether);
    }

    /**
     * @custom:scenario addOrderInTick is called with a tick higher than the max usable tick
     * @custom:given A tick higher than the max usable tick
     * @custom:when addOrderInTick is called
     * @custom:then the call reverts with a OrderManagerInvalidTick error
     */
    function test_RervertsWhen_tickIsHigherThanMaxTick() external {
        int24 tickSpacing = protocol.getTickSpacing();
        int24 tick = TickMath.maxUsableTick(tickSpacing) + tickSpacing;

        vm.expectRevert(abi.encodeWithSelector(OrderManagerInvalidTick.selector, tick));
        orderManager.addOrderInTick(tick, 1 ether);
    }

    /**
     * @custom:scenario addOrderInTick is called by a user that already has an order in the tick
     * @custom:given An order from a user in a tick
     * @custom:when addOrderInTick is called by the same user
     * @custom:then the call reverts with a OrderManagerUserAlreadyInTick error
     */
    function test_RervertsWhen_userAlreadyHasOrderInTick() external {
        int24 tick = protocol.getEffectiveTickForPrice(2000 ether);

        orderManager.addOrderInTick(tick, 1 ether);

        vm.expectRevert(abi.encodeWithSelector(OrderManagerUserAlreadyInTick.selector, address(this), tick, 0));
        orderManager.addOrderInTick(tick, 1 ether);
    }

    /* -------------------------------------------------------------------------- */
    /*                               addOrderInTick                               */
    /* -------------------------------------------------------------------------- */

    /**
     * @custom:scenario A user add an  order in a tick
     * @custom:given A user with a 1 ether balance
     * @custom:when That user calls addOrderInTick
     * @custom:then The order is created
     * @custom:and an OrderCreated event is emitted
     * @custom:and the funds are transferred from the user to the contract
     * @custom:and the state of the contract is updated
     */
    function test_addOrderInTick() external {
        int24 tick = protocol.getEffectiveTickForPrice(2000 ether);
        uint256 tickVersion = 0;
        uint256 expectedOrderIndex = 0;
        uint96 amount = 1 ether;
        uint256 orderManagerBalanceBefore = wstETH.balanceOf(address(orderManager));
        uint256 userBalanceBefore = wstETH.balanceOf(address(this));

        vm.expectEmit();
        emit OrderCreated(address(this), amount, tick, tickVersion, expectedOrderIndex);
        orderManager.addOrderInTick(tick, amount);

        assertEq(
            orderManagerBalanceBefore + amount,
            wstETH.balanceOf(address(orderManager)),
            "The assets were not sent to the order manager"
        );
        assertEq(userBalanceBefore - amount, wstETH.balanceOf(address(this)), "The assets were not taken from the user");

        IOrderManager.Order memory userOrder = orderManager.getOrderInTickAtIndex(tick, tickVersion, expectedOrderIndex);
        assertEq(userOrder.user, address(this), "Wrong user saved in the order");
        assertEq(userOrder.amountOfAssets, amount, "Wrong amount of assets saved in the order");

        IOrderManager.OrdersDataInTick memory ordersData = orderManager.getOrdersDataInTick(tick, tickVersion);
        assertEq(ordersData.amountOfAssets, amount, "The accumulated amount should be equal to the amount of the order");
        assertEq(ordersData.usedAmountOfAssetsRatio, 0, "The ratio of assets used should be 0");
    }

    /**
     * @custom:scenario 2 users add an order in the same tick
     * @custom:given 2 users with a balance of at least 1 ether
     * @custom:when That user calls addOrderInTick
     * @custom:then The order is created
     * @custom:and an OrderCreated event is emitted
     * @custom:and the funds are transferred from the user to the contract
     * @custom:and the state of the contract is updated
     */
    function testFuzz_addMultipleOrdersInTheSameTick() external {
        int24 tick = protocol.getEffectiveTickForPrice(2000 ether);
        uint256 tickVersion = 0;
        uint256 expectedOrderIndex = 0;
        uint96 amount = 1 ether;
        uint256 orderManagerBalanceBefore = wstETH.balanceOf(address(orderManager));
        uint256 userBalanceBefore = wstETH.balanceOf(address(this));

        vm.expectEmit();
        emit OrderCreated(address(this), amount, tick, tickVersion, expectedOrderIndex);
        orderManager.addOrderInTick(tick, amount);

        assertEq(
            orderManagerBalanceBefore + amount,
            wstETH.balanceOf(address(orderManager)),
            "The assets were not sent to the order manager"
        );
        assertEq(userBalanceBefore - amount, wstETH.balanceOf(address(this)), "The assets were not taken from the user");

        IOrderManager.Order memory userOrder = orderManager.getOrderInTickAtIndex(tick, tickVersion, expectedOrderIndex);
        assertEq(userOrder.user, address(this), "Wrong user saved in the order");
        assertEq(userOrder.amountOfAssets, amount, "Wrong amount of assets saved in the order");

        IOrderManager.OrdersDataInTick memory ordersData = orderManager.getOrdersDataInTick(tick, tickVersion);
        assertEq(
            ordersData.amountOfAssets, amount, "The accumulated amount should be equal to the amount of the only order"
        );
        assertEq(ordersData.usedAmountOfAssetsRatio, 0, "The ratio of assets used should be 0");

        /* -------------- Add one more order to check the accumulation -------------- */
        uint256 accumulatedAmountBefore = ordersData.amountOfAssets;
        expectedOrderIndex = 1;
        amount = 2 ether;

        vm.prank(USER_1);
        vm.expectEmit();
        emit OrderCreated(USER_1, amount, tick, tickVersion, expectedOrderIndex);
        orderManager.addOrderInTick(tick, amount);

        userOrder = orderManager.getOrderInTickAtIndex(tick, tickVersion, expectedOrderIndex);
        assertEq(userOrder.user, USER_1, "Wrong user saved in the order");
        assertEq(userOrder.amountOfAssets, amount, "Wrong amount of assets saved in the order");

        ordersData = orderManager.getOrdersDataInTick(tick, tickVersion);
        assertEq(
            ordersData.amountOfAssets, amount + accumulatedAmountBefore, "The accumulated amount of assets is wrong"
        );
        assertEq(ordersData.usedAmountOfAssetsRatio, 0, "The ratio of assets used should still be 0");
    }
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { IOrderManager } from "src/interfaces/OrderManager/IOrderManager.sol";
import { IOrderManagerErrors } from "src/interfaces/OrderManager/IOrderManagerErrors.sol";
import { IOrderManagerEvents } from "src/interfaces/OrderManager/IOrderManagerEvents.sol";

import { UsdnProtocolBaseFixture } from "test/unit/UsdnProtocol/utils/Fixtures.sol";

/**
 * @custom:feature Test the createPositionFromOrdersInTick function of the OrderManager contract
 * @custom:background Given a protocol initialized with default params
 * @custom:and 100 wstETH in the test contract
 * @custom:and an order in the 2000$ tick by the test contract
 */
contract TestOrderManagerCreatePositionFromOrdersInTick is
    UsdnProtocolBaseFixture,
    IOrderManagerErrors,
    IOrderManagerEvents
{
    uint128 internal _orderAmount = 1 ether;
    uint128 internal _orderPrice = 2000 ether;
    int24 internal _orderTick;
    uint256 internal _orderTickVersion;
    bytes32 internal _orderTickHash;

    function setUp() public {
        _setUp(DEFAULT_PARAMS);

        wstETH.mintAndApprove(address(this), 100 ether, address(orderManager), type(uint256).max);
        wstETH.approve(address(protocol), type(uint256).max);

        _orderTick = protocol.getEffectiveTickForPrice(_orderPrice);
        _orderTickVersion = 0;
        _orderTickHash = protocol.tickHash(_orderTick, _orderTickVersion);

        // Create an order
        orderManager.depositAssetsInTick(_orderTick, _orderAmount);
    }

    /* -------------------------------------------------------------------------- */
    /*                                   Reverts                                  */
    /* -------------------------------------------------------------------------- */

    /**
     * @custom:scenario Caller of createPositionFromOrdersInTick is not the USDN protocol
     * @custom:given An order in the 2000$ tick
     * @custom:when the caller of createPositionFromOrdersInTick is not the USDN Protocol
     * @custom:then the call reverts with a OrderManagerCallerIsNotUSDNProtocol error
     */
    function test_RevertWhen_createPositionFromOrdersInTickCallerNotUsdnProtocol() public {
        vm.expectRevert(abi.encodeWithSelector(OrderManagerCallerIsNotUSDNProtocol.selector, address(this)));
        orderManager.createPositionFromOrdersInTick(_orderPrice, _orderTickHash);
    }

    /* -------------------------------------------------------------------------- */
    /*                       createPositionFromOrdersInTick                       */
    /* -------------------------------------------------------------------------- */

    /**
     * @custom:scenario createPositionFromOrdersInTick is called but there are no orders in the provided tick
     * @custom:given No order in the 1000$ tick
     * @custom:when createPositionFromOrdersInTick is called
     * @custom:then it returns the PENDING_ORDERS_TICK constant and an amount of 0
     */
    function test_createPositionFromOrdersInTickDoesNothingIfNoOrderInTick() public {
        uint128 currentPrice = 1000 ether;
        int24 liquidatedTick = protocol.getEffectiveTickForPrice(currentPrice);
        bytes32 tickHash = protocol.tickHash(liquidatedTick, 0);

        vm.prank(address(protocol));
        (int24 longPositionTick, uint256 amount) = orderManager.createPositionFromOrdersInTick(currentPrice, tickHash);

        assertEq(
            longPositionTick, orderManager.PENDING_ORDERS_TICK(), "Tick should be the PENDING_ORDERS_TICK constant"
        );
        assertEq(amount, 0, "Amount should be 0");

        // Nothing should have been done to the orders data
        IOrderManager.OrdersDataInTick memory ordersData = orderManager.getOrdersDataInTick(liquidatedTick, 0);
        assertEq(ordersData.amountOfAssets, 0, "amountOfAssets should be the default value");
        assertEq(ordersData.longPositionTick, 0, "longPositionTick should be the default value");
        assertEq(ordersData.longPositionIndex, 0, "longPositionIndex should be the default value");
        assertEq(ordersData.longPositionTickVersion, 0, "longPositionTickVersion should be the default value");
    }

    /**
     * @custom:scenario createPositionFromOrdersInTick is called by the USDN Protocol with orders in the tick
     * @custom:given An order in the 2000$ tick
     * @custom:and An open position at the expected liquidation price of the order
     * @custom:when createPositionFromOrdersInTick is called
     * @custom:then the orders data in tick is updated with the long position's data
     * @custom:and the tick of the liquidation price for the long position is returned
     * @custom:and the amount available in the orders is returned
     */
    function test_createPositionFromOrdersInTick() public {
        uint128 expectedLiquidationPrice =
            protocol.i_getLiquidationPrice(_orderPrice, uint128(orderManager.getOrdersLeverage()));

        // Create an open position to make sure the index saved in OrdersDataInTick is correct
        protocol.initiateOpenPosition(1 ether, expectedLiquidationPrice, abi.encode(_orderPrice), EMPTY_PREVIOUS_DATA);

        int24 expectedLongTick = protocol.getEffectiveTickForPrice(expectedLiquidationPrice);

        vm.prank(address(protocol));
        (int24 longPositionTick, uint256 amount) =
            orderManager.createPositionFromOrdersInTick(_orderPrice, _orderTickHash);

        assertEq(expectedLongTick, longPositionTick, "Order has been created on the wrong tick");
        assertEq(amount, 1 ether, "Order has been created on the wrong tick");

        IOrderManager.OrdersDataInTick memory ordersData = orderManager.getOrdersDataInTick(_orderTick, 0);
        assertEq(ordersData.amountOfAssets, 1 ether, "amount in orders data should not have changed");
        assertEq(ordersData.longPositionTick, expectedLongTick, "tick of the long position equal the expected one");
        assertEq(ordersData.longPositionIndex, 1, "index of the long position should be 1");

        // TODO create test conditions where this is not 0?
        assertEq(ordersData.longPositionTickVersion, 0, "tick version of the long position should be 0");
    }
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

import { IOrderManagerErrors } from "src/interfaces/OrderManager/IOrderManagerErrors.sol";
import { IOrderManagerEvents } from "src/interfaces/OrderManager/IOrderManagerEvents.sol";
import { OrderManager } from "src/OrderManager.sol";

import { UsdnProtocolBaseFixture } from "test/unit/UsdnProtocol/utils/Fixtures.sol";
import { ADMIN } from "test/utils/Constants.sol";

/**
 * @custom:feature Test the admin functions of the OrderManager contract
 * @custom:background Given a protocol initialized with default params
 */
contract TestOrderManagerAdmin is UsdnProtocolBaseFixture, IOrderManagerErrors, IOrderManagerEvents {
    function setUp() public {
        _setUp(DEFAULT_PARAMS);
    }

    /* -------------------------------------------------------------------------- */
    /*                         approveAssetsForSpending()                         */
    /* -------------------------------------------------------------------------- */

    /**
     * @custom:scenario approveAssetsForSpending is called by a user different from the owner
     * @custom:given A user different from the owner
     * @custom:when approveAssetsForSpending is called
     * @custom:then the call reverts with a OwnableUnauthorizedAccount error
     */
    function test_RevertWhen_approveAssetsForSpendingCalledByNonOwner() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        orderManager.approveAssetsForSpending(1);
    }

    /**
     * @custom:scenario The owner of the contract calls approveAssetsForSpending
     * @custom:given An order manager contract
     * @custom:when approveAssetsForSpending is called
     * @custom:then The asset allowance of the usdn protocol on this contract should be the provided value
     */
    function test_approveAssetsForSpendingIncreaseAllowance() public {
        // Reset the allowance of the USDN protocol
        vm.prank(address(orderManager));
        wstETH.approve(address(protocol), 0);

        vm.prank(ADMIN);
        orderManager.approveAssetsForSpending(420);

        assertEq(
            protocol.getAsset().allowance(address(orderManager), address(protocol)),
            420,
            "The USDN protocol should be allowed to spend assets from the OrderManager contract"
        );
    }

    /* -------------------------------------------------------------------------- */
    /*                              setOrdersLeverage                             */
    /* -------------------------------------------------------------------------- */

    /**
     * @custom:scenario setOrdersLeverage is called by a user different from the owner
     * @custom:given A user different from the owner
     * @custom:when setOrdersLeverage is called
     * @custom:then the call reverts with a OwnableUnauthorizedAccount error
     */
    function test_RevertWhen_setOrdersLeverageCalledByNonOwner() public {
        uint256 leverageDecimals = protocol.LEVERAGE_DECIMALS();
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        orderManager.setOrdersLeverage(2 * 10 ** leverageDecimals);
    }

    /**
     * @custom:scenario setOrdersLeverage is called with a leverage that is higher than maxLeverage
     * @custom:given A value too high as the new leverage
     * @custom:when setOrdersLeverage is called
     * @custom:then the call reverts with a OrderManagerInvalidLeverage error
     */
    function test_RevertWhen_setOrdersLeverageCalledWithTooHighLeverage() public {
        uint256 maxLeverage = protocol.getMaxLeverage();

        vm.prank(ADMIN);
        vm.expectRevert(abi.encodeWithSelector(OrderManagerInvalidLeverage.selector));
        orderManager.setOrdersLeverage(maxLeverage + 1);
    }

    /**
     * @custom:scenario setOrdersLeverage is called with a leverage that is lower than minLeverage
     * @custom:given A value too low as the new leverage
     * @custom:when setOrdersLeverage is called
     * @custom:then the call reverts with a OrderManagerInvalidLeverage error
     */
    function test_RevertWhen_setOrdersLeverageCalledWithTooLowLeverage() public {
        uint256 minLeverage = protocol.getMinLeverage();

        vm.prank(ADMIN);
        vm.expectRevert(abi.encodeWithSelector(OrderManagerInvalidLeverage.selector));
        orderManager.setOrdersLeverage(minLeverage - 1);
    }

    /**
     * @custom:scenario setOrdersLeverage is called with a valid leverage value
     * @custom:given A leverage value inside limits
     * @custom:when setOrdersLeverage is called
     * @custom:then the OrdersLeverageUpdated event is emitted
     * @custom:and
     */
    function test_setOrdersLeverage() public {
        uint256 newLeverage = 2 * 10 ** uint256(protocol.LEVERAGE_DECIMALS());

        vm.prank(ADMIN);
        vm.expectEmit();
        emit OrdersLeverageUpdated(newLeverage);
        orderManager.setOrdersLeverage(newLeverage);

        assertEq(orderManager.getOrdersLeverage(), newLeverage, "The orders leverage should have been updated");
    }
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

import { OrderManager } from "src/OrderManager.sol";
import { InitializableReentrancyGuard } from "src/utils/InitializableReentrancyGuard.sol";

import { UsdnProtocolBaseFixture } from "test/unit/UsdnProtocol/utils/Fixtures.sol";

/**
 * @custom:feature Test the admin functions of the OrderManager contract
 * @custom:background Given a protocol initialized with default params
 */
contract TestOrderManagerAdmin is UsdnProtocolBaseFixture {
    function setUp() public {
        _setUp(DEFAULT_PARAMS);
    }

    /* -------------------------------------------------------------------------- */
    /*                                initialize()                                */
    /* -------------------------------------------------------------------------- */

    /**
     * @custom:scenario initialize is called by a user different from the owner
     * @custom:given A user different from the owner
     * @custom:when initialize is called
     * @custom:then the call reverts with a OwnableUnauthorizedAccount error
     */
    function test_RevertWhen_initializeCalledByNonOwner() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        orderManager.initialize(address(protocol));
    }

    /**
     * @custom:scenario initialize is called although the order manager contract has been initialized
     * @custom:given An initialized order manager contract
     * @custom:when initialize is called
     * @custom:then the call reverts with a InitializableReentrancyGuardUninitialized error
     */
    function test_RevertWhen_initializeCalledAfterInitialization() public adminPrank {
        vm.expectRevert(
            abi.encodeWithSelector(
                InitializableReentrancyGuard.InitializableReentrancyGuardInvalidInitialization.selector
            )
        );
        orderManager.initialize(address(protocol));
    }

    /**
     * @custom:scenario The owner of the contract calls the initialize function
     * @custom:given A non-initialized order manager contract
     * @custom:when initialize is called
     * @custom:then the contract is initialized with the usdn protocol address
     * @custom:then the asset allowance of the usdn protocol on this contract should the max value
     */
    function test_initialize() public adminPrank {
        OrderManager orderManager = new OrderManager();

        // Sanity check
        assertEq(
            orderManager.getUsdnProtocol(),
            address(0),
            "The USDN protocol address should not be set in order for this test to work"
        );

        orderManager.initialize(address(protocol));

        assertEq(orderManager.getUsdnProtocol(), address(protocol), "The USDN protocol address was not set");
        assertEq(
            protocol.getAsset().allowance(address(orderManager), address(protocol)),
            type(uint256).max,
            "The USDN protocol should be allowed to spend assets from the OrderManager contract"
        );
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
     * @custom:given A non-initialized order manager contract
     * @custom:when approveAssetsForSpending is called
     * @custom:then The asset allowance of the usdn protocol on this contract should the max value
     */
    function test_approveAssetsForSpendingSetAllowanceToMax() public adminPrank {
        orderManager.approveAssetsForSpending(420);

        assertEq(
            protocol.getAsset().allowance(address(orderManager), address(protocol)),
            420,
            "The USDN protocol should be allowed to spend assets from the OrderManager contract"
        );
    }
}

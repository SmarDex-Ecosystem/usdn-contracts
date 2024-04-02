// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

import { OrderManager } from "src/OrderManager.sol";

import { UsdnProtocolBaseFixture } from "test/unit/UsdnProtocol/utils/Fixtures.sol";
import { ADMIN } from "test/utils/Constants.sol";

/**
 * @custom:feature Test the admin functions of the OrderManager contract
 * @custom:background Given a protocol initialized with default params
 */
contract TestOrderManagerAdmin is UsdnProtocolBaseFixture {
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
    function test_approveAssetsForSpendingSetAllowanceToMax() public {
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
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { UsdnProtocolBaseFixture } from "test/unit/UsdnProtocol/utils/Fixtures.sol";

/**
 * @custom:feature Test of the protocol `_refundEther` function
 */
contract TestRefundEther is UsdnProtocolBaseFixture {
    function setUp() public {
        super._setUp(DEFAULT_PARAMS);
    }

    /**
     * @custom:scenario Test that the function reverts when to defined at zero
     * @custom:given A zero balance of the protocol
     * @custom:when The function is called with to defined at zero
     * @custom:then The transaction reverts with `UsdnProtocolInvalidAddressTo`
     */
    function test_RevertWhen_refundEther() public {
        vm.expectRevert(UsdnProtocolInvalidAddressTo.selector);
        protocol.i_refundEther(1 ether, address(0));
    }

    /**
     * @custom:scenario Test that the function reverts when call fails
     * @custom:given A zero balance of the protocol
     * @custom:when The function is called without enough ether in the contract
     * @custom:then The transaction reverts with `UsdnProtocolEtherRefundFailed`
     */
    function test_RevertWhen_refundEther_noReceive() public {
        vm.expectRevert(UsdnProtocolEtherRefundFailed.selector);
        protocol.i_refundEther{ value: 0.1 ether }(1 ether, address(1));
    }
}

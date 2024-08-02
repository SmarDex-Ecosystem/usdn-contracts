// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { UsdnProtocolBaseFixture } from "../utils/Fixtures.sol";

/**
 * @custom:feature Test of the protocol `_refundExcessEther` function
 */
contract TestRefundExcessEther is UsdnProtocolBaseFixture {
    function setUp() public {
        super._setUp(DEFAULT_PARAMS);
    }

    /**
     * @custom:scenario Test that the function reverts when wrong values are sent
     * @custom:given A zero balance of the protocol
     * @custom:when The function is called with the wrong values
     * @custom:then The transaction reverts with `UsdnProtocolUnexpectedBalance`
     */
    function test_RevertWhen_refundExcessEther() public {
        vm.expectRevert(UsdnProtocolUnexpectedBalance.selector);
        protocol.i_refundExcessEther(1, 0, 0);
    }

    /**
     * @custom:scenario Test that the function reverts when call fails
     * @custom:given A zero balance of the protocol
     * @custom:when The function is called with excess ether
     * @custom:and The sender doesn't accept ether
     * @custom:then The transaction reverts with `UsdnProtocolEtherRefundFailed`
     */
    function test_RevertWhen_refundExcessEther_noReceive() public {
        vm.expectRevert(UsdnProtocolEtherRefundFailed.selector);
        protocol.i_refundExcessEther{ value: 1 ether }(0, 1 ether, 0);
    }
}

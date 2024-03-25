// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { UsdnProtocolBaseFixture } from "test/unit/UsdnProtocol/utils/Fixtures.sol";

/**
 * @custom:feature Test of the protocol `_refundExcessEther` function
 */
contract TestRefundExcessEther is UsdnProtocolBaseFixture {
    function setUp() public {
        super._setUp(DEFAULT_PARAMS);
    }

    /**
     * @custom:scenario Test that the function reverts wrong values are sent to the function
     * @custom:given A zero balance of the protocol
     * @custom:then The function is called with the wrong values
     * @custom:when The transaction reverts with `UsdnProtocolUnexpectedBalance`
     */
    function test_refundExcessEther() public {
        vm.expectRevert(UsdnProtocolUnexpectedBalance.selector);
        protocol.i_refundExcessEther(1, 0, 0);
    }
}

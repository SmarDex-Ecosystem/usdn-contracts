// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { UsdnProtocolBaseFixture } from "test/unit/UsdnProtocol/utils/Fixtures.sol";

/**
 * @custom:feature Test of the protocol `_refundEther` function
 * @custom:background Given a protocol with a balance of 0.1 ether
 */
contract TestRefundEther is UsdnProtocolBaseFixture {
    function setUp() public {
        super._setUp(DEFAULT_PARAMS);
        vm.deal(address(protocol), 0.1 ether);
    }

    function test_refundEther() public {
        uint256 protocolBalance = address(protocol).balance;
        uint256 userBalance = address(this).balance;
        uint256 amount = 0.1 ether;

        protocol.i_refundEther(amount, address(this));

        assertEq(address(protocol).balance, protocolBalance - amount, "balance of the protocol");
        assertEq(address(this).balance, userBalance + amount, "balance of the user");
    }

    /**
     * @custom:scenario Test that the function reverts when to defined at zero
     * @custom:when The function is called with to defined at zero
     * @custom:then The transaction reverts with `UsdnProtocolInvalidAddressTo`
     */
    function test_RevertWhen_refundEther() public {
        vm.expectRevert(UsdnProtocolInvalidAddressTo.selector);
        protocol.i_refundEther(1 ether, address(0));
    }

    /**
     * @custom:scenario Test that the function reverts when call fails
     * @custom:when The function is called without enough ether in the contract
     * @custom:then The transaction reverts with `UsdnProtocolEtherRefundFailed`
     */
    function test_RevertWhen_refundEther_noReceive() public {
        vm.expectRevert(UsdnProtocolEtherRefundFailed.selector);
        protocol.i_refundEther{ value: 0.1 ether }(1 ether, address(1));
    }

    // receive ether refunds
    receive() external payable { }
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { USER_1 } from "test/utils/Constants.sol";
import { UsdnProtocolBaseFixture } from "test/unit/UsdnProtocol/utils/Fixtures.sol";

import { ProtocolAction } from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";

/**
 * @custom:feature Test of the protocol `_refundEther` function
 */
contract TestRefundEther is UsdnProtocolBaseFixture {
    function setUp() public {
        params = DEFAULT_PARAMS;
        params.flags.enableSecurityDeposit = true;
        super._setUp(params);
        setUpUserPositionInLong(
            OpenParams({
                user: address(this),
                untilAction: ProtocolAction.InitiateOpenPosition,
                positionSize: 1 ether,
                desiredLiqPrice: params.initialPrice - (params.initialPrice / 5),
                price: params.initialPrice
            })
        );
    }

    function test_refoundEther() public {
        uint256 protocolBalance = address(protocol).balance;
        uint256 userBalance = USER_1.balance;
        uint256 amount = 0.1 ether;

        protocol.i_refundEther(amount, USER_1);

        assertEq(address(protocol).balance, protocolBalance - amount, "balance of the protocol");
        assertEq(USER_1.balance, userBalance + amount, "balance of the user");
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
}

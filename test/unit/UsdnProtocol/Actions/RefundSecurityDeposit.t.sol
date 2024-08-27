// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { USER_1 } from "../../../utils/Constants.sol";
import { UsdnProtocolBaseFixture } from "../utils/Fixtures.sol";

import { IUsdnProtocolErrors } from "../../../../src/interfaces/UsdnProtocol/IUsdnProtocolErrors.sol";

/**
 * @custom:feature The security deposit refund of a not validated and liquidated position into USDN Protocol
 * @custom:background Given a protocol initialized with default params and a security deposit enabled
 */
contract TestUsdnProtocolRefundSecurityDeposit is UsdnProtocolBaseFixture {
    uint64 internal SECURITY_DEPOSIT_VALUE;

    function setUp() public {
        params = DEFAULT_PARAMS;
        params.flags.enableSecurityDeposit = true;
        super._setUp(params);
        wstETH.mintAndApprove(address(this), 1000 ether, address(protocol), type(uint256).max);

        SECURITY_DEPOSIT_VALUE = protocol.getSecurityDepositValue();
    }

    /**
     * @custom:scenario Refund security deposit after a position has been initiated and liquidated
     * @custom:given A deployed USDN protocol and a liquidated and not validated position with the caller as validator
     * @custom:when refundSecurityDeposit is called by the validator of the liquidated position
     * @custom:and The security deposit is refunded
     */
    function test_refundSecurityDepositAfterLiquidation() public {
        _initiateAndLiquidate();

        // snapshot balance
        uint256 balanceBefore = address(this).balance;

        // refund the security deposit
        protocol.refundSecurityDeposit();

        assertEq(address(this).balance, balanceBefore + SECURITY_DEPOSIT_VALUE, "security deposit refunded");
    }

    /**
     * @custom:scenario A user tries to get a security deposit refund without having a liquidated position
     * @custom:given A deployed USDN protocol and a liquidated and not validated position with another user as validator
     * @custom:when refundSecurityDeposit is called by a user that is not the validator of the liquidated position
     * @custom:then The user doesn't get a refund
     * @custom:and The user gets the error `UsdnProtocolNotEligibleForRefund`
     */
    function test_RevertWhen_RefundSecurityDepositWithoutLiquidation() public {
        _initiateAndLiquidate();

        // another user try to get a refund for his security deposit
        vm.prank(USER_1);
        vm.expectRevert(IUsdnProtocolErrors.UsdnProtocolNotEligibleForRefund.selector);
        protocol.refundSecurityDeposit();
    }

    /**
     * @custom:notice This function initiates with `address(this)` as validator a long position and liquidates it
     */
    function _initiateAndLiquidate() internal {
        // initiate a long position
        setUpUserPositionInLong(
            OpenParams({
                user: address(this),
                untilAction: ProtocolAction.InitiateOpenPosition,
                positionSize: 5 ether,
                desiredLiqPrice: params.initialPrice * 9 / 10,
                price: params.initialPrice
            })
        );
        skip(30 seconds);

        // liquidate the position with a price drop to $1000
        protocol.liquidate(abi.encode(1000 ether), 1);
    }

    receive() external payable { }
}

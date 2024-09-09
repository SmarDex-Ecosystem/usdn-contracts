// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { USER_1 } from "../../../utils/Constants.sol";
import { UsdnProtocolBaseFixture } from "../utils/Fixtures.sol";

import { IUsdnProtocolErrors } from "../../../../src/interfaces/UsdnProtocol/IUsdnProtocolErrors.sol";

/**
 * @custom:feature Refund of the security deposit for a stale pending action
 * @custom:background Given a protocol initialized with default params and security deposits enabled
 */
contract TestUsdnProtocolRefundSecurityDeposit is UsdnProtocolBaseFixture {
    uint64 internal _securityDepositValue;

    function setUp() public {
        params = DEFAULT_PARAMS;
        params.flags.enableSecurityDeposit = true;
        super._setUp(params);
        wstETH.mintAndApprove(address(this), 1000 ether, address(protocol), type(uint256).max);

        _securityDepositValue = protocol.getSecurityDepositValue();
    }

    /**
     * @custom:scenario Refund security deposit after a position has been initiated and liquidated
     * @custom:given A position that was liquidated before being validated
     * @custom:when refundSecurityDeposit is called by the validator of the liquidated position
     * @custom:and The security deposit is refunded
     */
    function test_refundSecurityDepositAfterLiquidation() public {
        _initiateAndLiquidate();

        uint256 balanceBefore = address(this).balance;
        protocol.refundSecurityDeposit();
        assertEq(address(this).balance, balanceBefore + _securityDepositValue, "security deposit refunded");
    }

    /**
     * @custom:scenario A user tries to get a security deposit refund without having a liquidated position
     * @custom:given A position that was liquidated before being validated
     * @custom:when refundSecurityDeposit is called by a user that is not the validator of the liquidated position
     * @custom:then The transaction reverts with `UsdnProtocolNotEligibleForRefund`
     */
    function test_RevertWhen_RefundSecurityDepositWithoutLiquidation() public {
        _initiateAndLiquidate();

        vm.prank(USER_1);
        vm.expectRevert(IUsdnProtocolErrors.UsdnProtocolNotEligibleForRefund.selector);
        protocol.refundSecurityDeposit();
    }

    /// @notice Helper function to initiate a long position and liquidate it before it gets validated
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

        // make sure the liquidation below uses a fresh price (mock oracle middleware gives price a few seconds in the
        // past)
        skip(1 minutes);

        // liquidate the position with a price drop to $1000
        protocol.liquidate(abi.encode(1000 ether), 1);
    }

    receive() external payable { }
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

import { ADMIN, USER_1 } from "../../../utils/Constants.sol";
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
        protocol.refundSecurityDeposit(payable(this));
        assertEq(address(this).balance, balanceBefore + _securityDepositValue, "security deposit refunded");
    }

    /**
     * @custom:scenario Refund security deposit for a validator that is not the msg.sender
     * @custom:given A position that was liquidated before being validated
     * @custom:when refundSecurityDeposit is called by a third party user
     * @custom:and The security deposit is refunded to the validator
     */
    function test_refundSecurityDepositFromAnyone() public {
        _initiateAndLiquidate();

        uint256 balanceBefore = address(this).balance;
        vm.prank(USER_1);
        protocol.refundSecurityDeposit(payable(this));
        assertEq(address(this).balance, balanceBefore + _securityDepositValue, "security deposit refunded");
    }

    /**
     * @custom:scenario Try to refund a security deposit for a user without a stale pending action
     * @custom:given A position that was liquidated before being validated
     * @custom:when refundSecurityDeposit is called with a validator that has no stale pending action
     * @custom:then The transaction reverts with `UsdnProtocolNotEligibleForRefund`
     */
    function test_RevertWhen_RefundSecurityDepositWithoutLiquidation() public {
        _initiateAndLiquidate();

        vm.expectRevert(abi.encodeWithSelector(IUsdnProtocolErrors.UsdnProtocolNotEligibleForRefund.selector, USER_1));
        protocol.refundSecurityDeposit(USER_1);
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

    /**
     * @custom:scenario Try to get the security deposit refunded with a paused protocol
     * @custom:given A liquidated user pending action
     * @custom:and A paused protocol
     * @custom:when The user calls refundSecurityDeposit
     * @custom:then The call reverts with `EnforcedPause`
     */
    function test_RevertWhen_refundSecurityDepositPaused() public {
        _initiateAndLiquidate();

        _pauseProtocol(ADMIN);
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        protocol.refundSecurityDeposit(payable(this));
    }

    receive() external payable { }
}

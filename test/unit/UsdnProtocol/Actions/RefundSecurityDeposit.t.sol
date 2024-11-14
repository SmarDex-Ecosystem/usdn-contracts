// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { USER_1, USER_2 } from "../../../utils/Constants.sol";
import { UsdnProtocolBaseFixture } from "../utils/Fixtures.sol";

import { IUsdnProtocolErrors } from "../../../../src/interfaces/UsdnProtocol/IUsdnProtocolErrors.sol";
import { InitializableReentrancyGuard } from "../../../../src/utils/InitializableReentrancyGuard.sol";

/**
 * @custom:feature Refund of the security deposit for a stale pending action
 * @custom:background Given a protocol initialized with default params and security deposits enabled
 */
contract TestUsdnProtocolRefundSecurityDeposit is UsdnProtocolBaseFixture {
    uint64 internal _securityDepositValue;
    bool internal _reentrancy;

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

    /**
     * @custom:scenario A malicious user attempts to attack the protocol via reentrancy on {refundSecurityDeposit}
     * @custom:given A malicious user (address(this)) with a stale pending action
     * @custom:and Another user (USER_2) also has a stale pending action
     * @custom:when A different user (USER_1) tries to initiate a position using the malicious user's address as the
     * validator
     * @custom:then The protocol reverts with `InitializableReentrancyGuardReentrantCall`
     */
    function test_RevertWhen_ReentrencyGriefing() public {
        uint256 securityDepositValue = protocol.getSecurityDepositValue();
        wstETH.mintAndApprove(USER_1, 5 ether, address(protocol), 5 ether);
        wstETH.mintAndApprove(USER_2, 5 ether, address(protocol), 5 ether);
        wstETH.mintAndApprove(address(this), 5 ether, address(protocol), 5 ether);
        uint256 maxLeverage = protocol.getMaxLeverage();
        bytes memory priceData = abi.encode(params.initialPrice);

        protocol.initiateOpenPosition{ value: securityDepositValue }(
            5 ether,
            params.initialPrice * 9 / 10,
            type(uint128).max,
            maxLeverage,
            address(this),
            payable(this),
            type(uint256).max,
            priceData,
            EMPTY_PREVIOUS_DATA
        );
        vm.prank(USER_2);
        protocol.initiateOpenPosition{ value: securityDepositValue }(
            5 ether,
            params.initialPrice * 9 / 10,
            type(uint128).max,
            maxLeverage,
            USER_2,
            USER_2,
            type(uint256).max,
            priceData,
            EMPTY_PREVIOUS_DATA
        );
        skip(1 minutes);
        // liquidate both initiated positions to put them in a stale state
        protocol.liquidate(abi.encode(params.initialPrice * 8 / 10));

        _reentrancy = true;

        vm.prank(USER_1);
        protocol.initiateOpenPosition{ value: securityDepositValue }(
            5 ether,
            params.initialPrice * 7 / 10,
            type(uint128).max,
            maxLeverage,
            USER_1,
            payable(this),
            type(uint256).max,
            abi.encode(params.initialPrice * 8 / 10),
            EMPTY_PREVIOUS_DATA
        );
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

        // make sure the liquidation below uses a fresh price
        // (mock oracle middleware gives price a few seconds in the past)
        skip(1 minutes);

        // liquidate the position with a price drop to $1000
        protocol.liquidate(abi.encode(1000 ether));
    }

    receive() external payable {
        if (_reentrancy) {
            _reentrancy = false;
            vm.expectRevert(InitializableReentrancyGuard.InitializableReentrancyGuardReentrantCall.selector);
            protocol.refundSecurityDeposit(USER_2);
        }
    }
}

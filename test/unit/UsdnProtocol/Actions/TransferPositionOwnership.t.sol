// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { USER_1 } from "../../../utils/Constants.sol";
import { DelegationSignatureUtils } from "../../../utils/DelegationSignatureUtils.sol";
import { UsdnProtocolBaseFixture } from "../utils/Fixtures.sol";
import { OwnershipCallbackHandler } from "../utils/OwnershipCallbackHandler.sol";

/// @custom:feature The `transferPositionOwnership` function of the USDN protocol
contract TestUsdnProtocolTransferPositionOwnership is UsdnProtocolBaseFixture, DelegationSignatureUtils {
    OwnershipCallbackHandler callbackHandler;

    function setUp() public {
        super._setUp(DEFAULT_PARAMS);

        callbackHandler = new OwnershipCallbackHandler();
    }

    /**
     * @custom:scenario Transfer position ownership after a position has been initiated
     * @custom:given A position that has been initiated
     * @custom:when The position ownership is transferred
     * @custom:then The position's owner is changed
     * @custom:and The pending action's validator is unchanged
     * @custom:and The `PositionOwnershipTransferred` event is emitted
     * @custom:and The position can be validated by validator
     */
    function test_transferOwnershipAfterInitiateOpen() public {
        PositionId memory posId = setUpUserPositionInLong(
            OpenParams({
                user: address(this),
                untilAction: ProtocolAction.InitiateOpenPosition,
                positionSize: 1 ether,
                desiredLiqPrice: params.initialPrice / 2,
                price: params.initialPrice
            })
        );

        vm.expectEmit();
        emit PositionOwnershipTransferred(posId, address(this), USER_1);
        protocol.transferPositionOwnership(posId, USER_1, "");

        (Position memory pos,) = protocol.getLongPosition(posId);
        assertEq(pos.user, USER_1, "position user");

        // changing ownership does not change the validator address
        PendingAction memory action = protocol.getUserPendingAction(address(this));
        assertEq(action.validator, address(this), "pending action validator");

        protocol.validateOpenPosition(payable(address(this)), abi.encode(params.initialPrice), EMPTY_PREVIOUS_DATA);
    }

    /**
     * @custom:scenario Transfer position ownership after a position has been validated
     * @custom:given A position that has been validated
     * @custom:when The position ownership is transferred
     * @custom:then The position's owner is changed
     * @custom:and The `PositionOwnershipTransferred` event is emitted
     * @custom:and The position can be closed by the new owner
     */
    function test_transferOwnershipAfterValidateOpen() public {
        PositionId memory posId = setUpUserPositionInLong(
            OpenParams({
                user: address(this),
                untilAction: ProtocolAction.ValidateOpenPosition,
                positionSize: 1 ether,
                desiredLiqPrice: params.initialPrice / 2,
                price: params.initialPrice
            })
        );

        vm.expectEmit();
        emit PositionOwnershipTransferred(posId, address(this), USER_1);
        protocol.transferPositionOwnership(posId, USER_1, "");

        (Position memory pos,) = protocol.getLongPosition(posId);
        assertEq(pos.user, USER_1, "position user");

        vm.prank(USER_1);
        protocol.initiateClosePosition(
            posId,
            pos.amount,
            DISABLE_MIN_PRICE,
            USER_1,
            USER_1,
            type(uint256).max,
            abi.encode(params.initialPrice),
            EMPTY_PREVIOUS_DATA,
            ""
        );

        // the close action should have USER_1 as the validator
        PendingAction memory action = protocol.getUserPendingAction(USER_1);
        assertEq(action.validator, USER_1, "pending action validator");
    }

    /**
     * @custom:scenario Transfer position ownership to a contract that implements the ownership callback interface
     * @custom:given A position that has been validated
     * @custom:when The position ownership is transferred to a contract that implements the ownership callback interface
     * @custom:then The position's owner is changed
     * @custom:and The callback function is called on the new owner
     */
    function test_transferOwnershipCallback() public {
        PositionId memory posId = setUpUserPositionInLong(
            OpenParams({
                user: address(this),
                untilAction: ProtocolAction.ValidateOpenPosition,
                positionSize: 1 ether,
                desiredLiqPrice: params.initialPrice / 2,
                price: params.initialPrice
            })
        );

        vm.expectEmit();
        emit TestOwnershipCallback(address(this), posId);
        protocol.transferPositionOwnership(posId, address(callbackHandler), "");
    }

    /**
     * @custom:scenario Transfer position ownership to a contract that implements the ownership callback but fails
     * @custom:given A position that has been validated
     * @custom:and A new owner reverts in the callback
     * @custom:when The position ownership is transferred
     * @custom:then The transaction reverts
     */
    function test_RevertWhen_transferOwnershipCallbackFails() public {
        PositionId memory posId = setUpUserPositionInLong(
            OpenParams({
                user: address(this),
                untilAction: ProtocolAction.ValidateOpenPosition,
                positionSize: 1 ether,
                desiredLiqPrice: params.initialPrice / 2,
                price: params.initialPrice
            })
        );

        callbackHandler.setShouldFail(true);
        vm.expectRevert(OwnershipCallbackFailure.selector);
        protocol.transferPositionOwnership(posId, address(callbackHandler), "");
    }

    /**
     * @custom:scenario Transfer position ownership after a position has been initiated to close
     * @custom:given A position that has been initiated to close
     * @custom:when The position ownership is transferred
     * @custom:then The transaction reverts with `UsdnProtocolUnauthorized`
     */
    function test_RevertWhen_transferOwnershipAfterInitiateClose() public {
        PositionId memory posId = setUpUserPositionInLong(
            OpenParams({
                user: address(this),
                untilAction: ProtocolAction.InitiateClosePosition,
                positionSize: 1 ether,
                desiredLiqPrice: params.initialPrice / 2,
                price: params.initialPrice
            })
        );

        vm.expectRevert(UsdnProtocolUnauthorized.selector);
        protocol.transferPositionOwnership(posId, USER_1, "");
    }

    /**
     * @custom:scenario Transfer position ownership when the caller is not the owner
     * @custom:given A position that has been validated
     * @custom:when The position ownership is transferred by a user that is not the owner
     * @custom:then The transaction reverts with `UsdnProtocolUnauthorized`
     */
    function test_RevertWhen_transferOwnershipNotOwner() public {
        PositionId memory posId = setUpUserPositionInLong(
            OpenParams({
                user: address(this),
                untilAction: ProtocolAction.ValidateOpenPosition,
                positionSize: 1 ether,
                desiredLiqPrice: params.initialPrice / 2,
                price: params.initialPrice
            })
        );

        vm.expectRevert(UsdnProtocolUnauthorized.selector);
        vm.prank(USER_1);
        protocol.transferPositionOwnership(posId, USER_1, "");
    }

    /**
     * @custom:scenario Transfer position ownership to the zero address
     * @custom:given A position that has been validated
     * @custom:when The position ownership is transferred to the zero address
     * @custom:then The transaction reverts with `UsdnProtocolInvalidAddressTo`
     */
    function test_RevertWhen_transferOwnershipToZero() public {
        PositionId memory posId = setUpUserPositionInLong(
            OpenParams({
                user: address(this),
                untilAction: ProtocolAction.ValidateOpenPosition,
                positionSize: 1 ether,
                desiredLiqPrice: params.initialPrice / 2,
                price: params.initialPrice
            })
        );

        vm.expectRevert(UsdnProtocolInvalidAddressTo.selector);
        protocol.transferPositionOwnership(posId, address(0), "");
    }

    /**
     * @custom:scenario Transfer position ownership after a position has been liquidated
     * @custom:given A position that has been liquidated
     * @custom:when The position ownership is transferred
     * @custom:then The transaction reverts with `UsdnProtocolOutdatedTick`
     */
    function test_RevertWhen_transferOwnershipAfterLiq() public {
        PositionId memory posId = setUpUserPositionInLong(
            OpenParams({
                user: address(this),
                untilAction: ProtocolAction.ValidateOpenPosition,
                positionSize: 1 ether,
                desiredLiqPrice: params.initialPrice / 2,
                price: params.initialPrice
            })
        );

        _waitBeforeLiquidation();
        protocol.liquidate(abi.encode(params.initialPrice / 3));

        vm.expectRevert(
            abi.encodeWithSelector(UsdnProtocolOutdatedTick.selector, posId.tickVersion + 1, posId.tickVersion)
        );
        protocol.transferPositionOwnership(posId, USER_1, "");
    }

    /**
     * @custom:scenario Transfer position ownership after a position has been validated using delegation signature
     * @custom:given A position that has been validated
     * @custom:given A valid delegation signature
     * @custom:when The {transferPositionOwnership} function is called
     * @custom:then The position's ownership is transferred
     */
    function test_transferPositionOwnershipDelegation() public {
        uint256 privateKey = 1;
        address user = vm.addr(privateKey);
        uint256 initialNonce = protocol.getNonce(user);
        PositionId memory posId = setUpUserPositionInLong(
            OpenParams({
                user: user,
                untilAction: ProtocolAction.ValidateOpenPosition,
                positionSize: 1 ether,
                desiredLiqPrice: params.initialPrice / 2,
                price: params.initialPrice
            })
        );

        (Position memory pos,) = protocol.getLongPosition(posId);
        assertEq(pos.user, user, "the current position user should be `user`");

        TransferPositionOwnershipDelegation memory delegation = TransferPositionOwnershipDelegation({
            posIdHash: keccak256(abi.encode(posId)),
            positionOwner: user,
            newPositionOwner: address(callbackHandler),
            delegatedAddress: address(this),
            nonce: initialNonce
        });

        bytes memory delegationSignature =
            _getTransferPositionDelegationSignature(privateKey, protocol.domainSeparatorV4(), delegation);

        vm.expectEmit();
        emit TestOwnershipCallback(user, posId);
        vm.expectEmit();
        emit PositionOwnershipTransferred(posId, user, address(callbackHandler));
        protocol.transferPositionOwnership(posId, address(callbackHandler), delegationSignature);

        (pos,) = protocol.getLongPosition(posId);
        assertEq(pos.user, address(callbackHandler), "the new position user should be the `callbackHandler`");
        assertEq(protocol.getNonce(user), initialNonce + 1, "the user nonce should be incremented");
    }
}

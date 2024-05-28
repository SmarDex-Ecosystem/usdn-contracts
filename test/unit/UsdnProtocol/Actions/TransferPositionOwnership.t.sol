// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { USER_1 } from "test/utils/Constants.sol";
import { UsdnProtocolBaseFixture } from "test/unit/UsdnProtocol/utils/Fixtures.sol";
import { OwnershipCallbackHandler } from "test/unit/UsdnProtocol/utils/OwnershipCallbackHandler.sol";

import { ProtocolAction, PositionId, Position, PendingAction } from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";

/// @custom:feature The `transferPositionOwnership` function of the USDN protocol
contract TestUsdnProtocolTransferPositionOwnership is UsdnProtocolBaseFixture {
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
        emit PositionOwnershipTransferred(address(this), USER_1, posId);
        protocol.transferPositionOwnership(posId, USER_1);

        (Position memory pos,) = protocol.getLongPosition(posId);
        assertEq(pos.user, USER_1, "position user");

        // changing ownership does not change the validator address
        PendingAction memory action = protocol.getUserPendingAction(address(this));
        assertEq(action.validator, address(this), "pending action validator");

        protocol.validateOpenPosition(address(this), abi.encode(params.initialPrice), EMPTY_PREVIOUS_DATA);
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
        emit PositionOwnershipTransferred(address(this), USER_1, posId);
        protocol.transferPositionOwnership(posId, USER_1);

        (Position memory pos,) = protocol.getLongPosition(posId);
        assertEq(pos.user, USER_1, "position user");

        vm.prank(USER_1);
        protocol.initiateClosePosition(posId, pos.amount, USER_1, abi.encode(params.initialPrice), EMPTY_PREVIOUS_DATA);

        // the close action should have USER_1 as the validator
        PendingAction memory action = protocol.getUserPendingAction(USER_1);
        assertEq(action.validator, USER_1, "pending action validator");
    }

    /**
     * @custom:scenario Transfer position ownership to a contract that implements the ownership callback
     * @custom:given A position that has been validated
     * @custom:when The position ownership is transferred to a contract that implements the ownership callback
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
        protocol.transferPositionOwnership(posId, address(callbackHandler));
    }

    /**
     * @custom:scenario Transfer position ownership to a contract that implements the ownership callback but fails
     * @custom:given A position that has been validated
     * @custom:and A new owner that does not successfully implement the ownership callback (reverts)
     * @custom:when The position ownership is transferred to the new owner
     * @custom:then The position's owner is changed
     * @custom:and The transaction does not revert
     */
    function test_transferOwnershipCallbackFails() public {
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
        protocol.transferPositionOwnership(posId, address(callbackHandler));
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
        protocol.transferPositionOwnership(posId, USER_1);
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
        protocol.transferPositionOwnership(posId, USER_1);
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
        protocol.transferPositionOwnership(posId, address(0));
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
        protocol.liquidate(abi.encode(params.initialPrice / 3), 10);

        vm.expectRevert(
            abi.encodeWithSelector(UsdnProtocolOutdatedTick.selector, posId.tickVersion + 1, posId.tickVersion)
        );
        protocol.transferPositionOwnership(posId, USER_1);
    }
}

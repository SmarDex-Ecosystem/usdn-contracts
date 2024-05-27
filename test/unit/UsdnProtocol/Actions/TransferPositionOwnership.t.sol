// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { USER_1 } from "test/utils/Constants.sol";
import { UsdnProtocolBaseFixture } from "test/unit/UsdnProtocol/utils/Fixtures.sol";

import { ProtocolAction, PositionId, Position, PendingAction } from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";

/// @custom:feature The `transferPositionOwnership` function of the USDN protocol
contract TestUsdnProtocolTransferPositionOwnership is UsdnProtocolBaseFixture {
    function setUp() public {
        super._setUp(DEFAULT_PARAMS);
    }

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

        protocol.transferPositionOwnership(posId, USER_1);

        (Position memory pos,) = protocol.getLongPosition(posId);
        assertEq(pos.user, USER_1, "position user");

        // changing ownership does not change the validator address
        PendingAction memory action = protocol.getUserPendingAction(address(this));
        assertEq(action.validator, address(this), "pending action validator");

        protocol.validateOpenPosition(address(this), abi.encode(params.initialPrice), EMPTY_PREVIOUS_DATA);
    }

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

        protocol.transferPositionOwnership(posId, USER_1);

        (Position memory pos,) = protocol.getLongPosition(posId);
        assertEq(pos.user, USER_1, "position user");

        vm.prank(USER_1);
        protocol.initiateClosePosition(posId, pos.amount, USER_1, abi.encode(params.initialPrice), EMPTY_PREVIOUS_DATA);

        // the close action should have USER_1 as the validator
        PendingAction memory action = protocol.getUserPendingAction(USER_1);
        assertEq(action.validator, USER_1, "pending action validator");
    }

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

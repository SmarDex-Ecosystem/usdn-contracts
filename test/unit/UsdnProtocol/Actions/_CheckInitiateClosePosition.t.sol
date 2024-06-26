// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import { ADMIN, USER_1, USER_2 } from "../../../utils/Constants.sol";
import { UsdnProtocolBaseFixture } from "../utils/Fixtures.sol";
import { MockRebalancer } from "../utils/MockRebalancer.sol";

import { IRebalancerTypes } from "../../../../src/interfaces/Rebalancer/IRebalancerTypes.sol";

/**
 * @custom:feature The `_checkInitiateClosePosition` function
 * @custom:background Given a user position that can be closed and a non-zero minimum amount on long positions
 */
contract TestUsdnProtocolCheckInitiateClosePosition is UsdnProtocolBaseFixture, IRebalancerTypes {
    uint128 constant AMOUNT = 5 ether;

    MockRebalancer mockedRebalancer;
    PositionId posId;
    Position pos;

    function setUp() public {
        params = DEFAULT_PARAMS;
        params.flags.enableLongLimit = true;
        super._setUp(params);

        mockedRebalancer = new MockRebalancer();
        vm.prank(ADMIN);
        protocol.setRebalancer(mockedRebalancer);

        posId = setUpUserPositionInLong(
            OpenParams(
                address(this), ProtocolAction.ValidateOpenPosition, AMOUNT, params.initialPrice / 2, params.initialPrice
            )
        );
        (pos,) = protocol.getLongPosition(posId);
    }

    function test_setUpAmount() public {
        assertGt(protocol.getMinLongPosition(), 0, "min position");
        assertGt(AMOUNT, protocol.getMinLongPosition(), "position amount");
    }

    function test_checkInitiateClosePosition() public view {
        uint128 amountToClose = AMOUNT - uint128(protocol.getMinLongPosition());

        protocol.i_checkInitiateClosePosition(address(this), USER_1, USER_2, amountToClose, pos);
        protocol.i_checkInitiateClosePosition(address(this), USER_1, USER_2, AMOUNT, pos);
    }

    function test_RevertWhen_checkInitiateClosePositionToZero() public {
        vm.expectRevert(UsdnProtocolInvalidAddressTo.selector);
        protocol.i_checkInitiateClosePosition(address(this), address(0), USER_2, AMOUNT, pos);
    }

    function test_RevertWhen_checkInitiateClosePositionValidatorZero() public {
        vm.expectRevert(UsdnProtocolInvalidAddressValidator.selector);
        protocol.i_checkInitiateClosePosition(address(this), USER_1, address(0), AMOUNT, pos);
    }

    function test_RevertWhen_checkInitiateClosePositionWrongOwner() public {
        vm.expectRevert(UsdnProtocolUnauthorized.selector);
        protocol.i_checkInitiateClosePosition(USER_1, USER_1, USER_2, AMOUNT, pos);
    }

    function test_RevertWhen_checkInitiateClosePositionPending() public {
        posId = setUpUserPositionInLong(
            OpenParams(
                address(this), ProtocolAction.InitiateOpenPosition, AMOUNT, params.initialPrice / 2, params.initialPrice
            )
        );
        (pos,) = protocol.getLongPosition(posId);
        vm.expectRevert(UsdnProtocolPositionNotValidated.selector);
        protocol.i_checkInitiateClosePosition(address(this), USER_1, USER_2, AMOUNT, pos);
    }

    function test_RevertWhen_checkInitiateClosePositionAmountTooBig() public {
        uint128 amountToClose = 2 * AMOUNT;
        vm.expectRevert(
            abi.encodeWithSelector(UsdnProtocolAmountToCloseHigherThanPositionAmount.selector, amountToClose, AMOUNT)
        );
        protocol.i_checkInitiateClosePosition(address(this), USER_1, USER_2, amountToClose, pos);
    }

    function test_RevertWhen_checkInitiateClosePositionAmountZero() public {
        vm.expectRevert(UsdnProtocolAmountToCloseIsZero.selector);
        protocol.i_checkInitiateClosePosition(address(this), USER_1, USER_2, 0, pos);
    }

    function test_RevertWhen_checkInitiateClosePositionRemainingLow() public {
        uint128 amountToClose = AMOUNT - uint128(protocol.getMinLongPosition()) + 1;
        vm.expectRevert(UsdnProtocolLongPositionTooSmall.selector);
        protocol.i_checkInitiateClosePosition(address(this), USER_1, USER_2, amountToClose, pos);
    }

    function test_checkInitiateClosePositionFromRebalancer() public {
        uint128 amountToClose = AMOUNT - uint128(protocol.getMinLongPosition()) + 1;
        _setUpRebalancerPosition(uint88(amountToClose));
        // note: the "to" below must be the rebalancer user (USER_1)
        protocol.i_checkInitiateClosePosition(address(mockedRebalancer), USER_1, USER_2, amountToClose, pos);

        amountToClose -= 1;
        // if the rebalancer position remains above the position limit, then the "to" can be anyone
        protocol.i_checkInitiateClosePosition(address(mockedRebalancer), address(this), USER_2, amountToClose, pos);
    }

    function test_RevertWhen_checkInitiateClosePositionFromRebalancerTooSmall() public {
        uint128 amountToClose = AMOUNT - uint128(protocol.getMinLongPosition()) + 1;
        _setUpRebalancerPosition(uint88(amountToClose + 1));
        // note: the "to" below must be the rebalancer user (USER_1)
        vm.expectRevert(UsdnProtocolLongPositionTooSmall.selector);
        protocol.i_checkInitiateClosePosition(address(mockedRebalancer), USER_1, USER_2, amountToClose, pos);
    }

    function _setUpRebalancerPosition(uint88 userAmount) internal {
        assertLe(userAmount, AMOUNT, "rebalancer user amount");
        posId = setUpUserPositionInLong(
            OpenParams(
                address(mockedRebalancer),
                ProtocolAction.ValidateOpenPosition,
                AMOUNT,
                params.initialPrice / 2,
                params.initialPrice
            )
        );
        (pos,) = protocol.getLongPosition(posId);
        mockedRebalancer.setCurrentStateData(0, protocol.getMaxLeverage(), posId);
        UserDeposit memory userDeposit = UserDeposit({
            initiateTimestamp: uint40(block.timestamp),
            amount: userAmount,
            entryPositionVersion: mockedRebalancer.getPositionVersion()
        });
        mockedRebalancer.setUserDepositData(USER_1, userDeposit);
    }
}

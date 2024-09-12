// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

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

    function test_setUpAmount() public view {
        assertGt(protocol.getMinLongPosition(), 0, "min position");
        assertGt(AMOUNT, protocol.getMinLongPosition(), "position amount");
    }

    /**
     * @custom:scenario Check a valid initiate close position
     * @custom:when The user initiates a close position with valid parameters
     * @custom:then The function should not revert
     */
    function test_checkInitiateClosePosition() public view {
        uint128 amountToClose = AMOUNT - uint128(protocol.getMinLongPosition());

        protocol.i_checkInitiateClosePosition(address(this), USER_1, USER_2, amountToClose, pos);
        protocol.i_checkInitiateClosePosition(address(this), USER_1, USER_2, AMOUNT, pos);
    }

    /**
     * @custom:scenario Check an initiate close with a zero "to" address
     * @custom:when The user initiates a close position with a zero "to" address
     * @custom:then The function should revert with `UsdnProtocolInvalidAddressTo`
     */
    function test_RevertWhen_checkInitiateClosePositionToZero() public {
        vm.expectRevert(UsdnProtocolInvalidAddressTo.selector);
        protocol.i_checkInitiateClosePosition(address(this), address(0), USER_2, AMOUNT, pos);
    }

    /**
     * @custom:scenario Check an initiate close with a zero "validator" address
     * @custom:when The user initiates a close position with a zero "validator" address
     * @custom:then The function should revert with `UsdnProtocolInvalidAddressValidator`
     */
    function test_RevertWhen_checkInitiateClosePositionValidatorZero() public {
        vm.expectRevert(UsdnProtocolInvalidAddressValidator.selector);
        protocol.i_checkInitiateClosePosition(address(this), USER_1, address(0), AMOUNT, pos);
    }

    /**
     * @custom:scenario Check an initiate close with a wrong owner
     * @custom:when The protocol initiates a close position with a wrong owner (should never happen)
     * @custom:then The function should revert with `UsdnProtocolUnauthorized`
     */
    function test_RevertWhen_checkInitiateClosePositionWrongOwner() public {
        vm.expectRevert(UsdnProtocolUnauthorized.selector);
        protocol.i_checkInitiateClosePosition(USER_1, USER_1, USER_2, AMOUNT, pos);
    }

    /**
     * @custom:scenario Check an initiate close of a position that was not validated
     * @custom:given A position that was initiated but not validated
     * @custom:when The user initiates a close position of a position that was not validated
     * @custom:then The function should revert with `UsdnProtocolPositionNotValidated`
     */
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

    /**
     * @custom:scenario Check an initiate close of a position with invalid amount
     * @custom:when The user initiates a close position with an amount that is too big
     * @custom:then The function should revert with `UsdnProtocolAmountToCloseHigherThanPositionAmount`
     */
    function test_RevertWhen_checkInitiateClosePositionAmountTooBig() public {
        uint128 amountToClose = 2 * AMOUNT;
        vm.expectRevert(
            abi.encodeWithSelector(UsdnProtocolAmountToCloseHigherThanPositionAmount.selector, amountToClose, AMOUNT)
        );
        protocol.i_checkInitiateClosePosition(address(this), USER_1, USER_2, amountToClose, pos);
    }

    /**
     * @custom:scenario Check an initiate close of a position with zero amount
     * @custom:when The user initiates a close position with an amount of zero
     * @custom:then The function should revert with `UsdnProtocolZeroAmount`
     */
    function test_RevertWhen_checkInitiateClosePositionAmountZero() public {
        vm.expectRevert(UsdnProtocolZeroAmount.selector);
        protocol.i_checkInitiateClosePosition(address(this), USER_1, USER_2, 0, pos);
    }

    /**
     * @custom:scenario Check an initiate close of a position with a remaining amount that is too low
     * @custom:when The user initiates a partial close with an amount that would leave the position below the minimum
     * @custom:then The function should revert with `UsdnProtocolLongPositionTooSmall`
     */
    function test_RevertWhen_checkInitiateClosePositionRemainingLow() public {
        uint128 amountToClose = AMOUNT - uint128(protocol.getMinLongPosition()) + 1;
        vm.expectRevert(UsdnProtocolLongPositionTooSmall.selector);
        protocol.i_checkInitiateClosePosition(address(this), USER_1, USER_2, amountToClose, pos);
    }

    /**
     * @custom:scenario Check an initiate close of a position from the rebalancer with a remaining amount that is too
     * low
     * @custom:given USER_1 has a position in the rebalancer with an amount that leaves the position below the min
     * @custom:and The "validator" address is the rebalancer user
     * @custom:when The rebalancer initiates a close position with the full amount of USER_1
     * @custom:then The function should not revert
     */
    function test_checkInitiateClosePositionFromRebalancerBelowMin() public {
        uint128 amountToClose = AMOUNT - uint128(protocol.getMinLongPosition()) + 1;
        _setUpRebalancerPosition(uint88(amountToClose));
        // note: the rebalancer always sets the rebalancer user as "validator" (USER_1)
        protocol.i_checkInitiateClosePosition(address(mockedRebalancer), USER_2, USER_1, amountToClose, pos);
    }

    /**
     * @custom:scenario Check an initiate close of a position from the rebalancer (partial)
     * @custom:given USER_1 has a position in the rebalancer with an amount that leaves the position above the min
     * @custom:and The "validator" address is the rebalancer user
     * @custom:when The rebalancer initiates a partial close position with a remaining amount that is above the min
     * @custom:then The function should not revert
     */
    function test_checkInitiateClosePositionFromRebalancer() public {
        uint128 amountToClose = AMOUNT - uint128(protocol.getMinLongPosition());
        _setUpRebalancerPosition(uint88(amountToClose + 1));
        // note: the rebalancer always sets the rebalancer user as "validator" (USER_1)
        protocol.i_checkInitiateClosePosition(address(mockedRebalancer), USER_2, USER_1, amountToClose, pos);
    }

    /**
     * @custom:scenario Check an initiate close of a position from the rebalancer with a remaining amount that is too
     * low
     * @custom:given USER_1 has a position in the rebalancer with an amount that would leave the position below the min
     * @custom:and The "validator" address is the rebalancer user
     * @custom:when The rebalancer initiates a partial close position with an amount below their position amount
     * @custom:then The function should revert with `UsdnProtocolLongPositionTooSmall`
     */
    function test_RevertWhen_checkInitiateClosePositionFromRebalancerTooSmall() public {
        uint128 amountToClose = AMOUNT - uint128(protocol.getMinLongPosition()) + 1;
        _setUpRebalancerPosition(uint88(amountToClose + 1));
        // note: the rebalancer always sets the rebalancer user as "validator" (USER_1)
        vm.expectRevert(UsdnProtocolLongPositionTooSmall.selector);
        protocol.i_checkInitiateClosePosition(address(mockedRebalancer), USER_2, USER_1, amountToClose, pos);
    }

    /**
     * @notice Helper function to setup the mock rebalancer
     * @param userAmount The amount to set for the user deposit
     */
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

        // TO DO : change the hardcoded value to a variable
        mockedRebalancer.setCurrentStateData(0, protocol.getMaxLeverage(), 10 ** 21 + 10 ** 12, posId);
        UserDeposit memory userDeposit = UserDeposit({
            initiateTimestamp: uint40(block.timestamp),
            amount: userAmount,
            entryPositionVersion: mockedRebalancer.getPositionVersion()
        });
        mockedRebalancer.setUserDepositData(USER_1, userDeposit);
    }
}

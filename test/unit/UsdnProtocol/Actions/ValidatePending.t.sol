// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { USER_1, USER_2, USER_3, USER_4 } from "test/utils/Constants.sol";
import { UsdnProtocolBaseFixture } from "test/unit/UsdnProtocol/utils/Fixtures.sol";

import { PendingAction, ProtocolAction, PreviousActionsData } from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";

/**
 * @custom:feature The validateActionablePendingActions function of the USDN Protocol
 * @custom:given A protocol with all fees, rebase and funding disabled
 */
contract TestUsdnProtocolValidatePending is UsdnProtocolBaseFixture {
    function setUp() public {
        _setUp(DEFAULT_PARAMS);
    }

    /**
     * @custom:scenario Validate four pending actions manually
     * @custom:given A protocol with four pending actions (one of each type, all different users)
     * @custom:when The actions are validated manually with the correct calldata
     * @custom:and a maxValidations above the number of pending actions
     * @custom:then All four actions are validated and the returned count is 4
     * @custom:and the pending actions are removed
     */
    function test_validateActionablePendingActions() public {
        PreviousActionsData memory previousActionsData = _setUpFourPendingActions();

        vm.expectEmit(true, false, false, false);
        emit ValidatedOpenPosition(USER_1, 0, 0, 0, 0, 0);
        vm.expectEmit(true, false, false, false);
        emit ValidatedClosePosition(USER_2, 0, 0, 0, 0, 0);
        vm.expectEmit(true, false, false, false);
        emit ValidatedDeposit(USER_3, 0, 0, 0);
        vm.expectEmit(true, false, false, false);
        emit ValidatedWithdrawal(USER_4, 0, 0, 0);
        uint256 validated = protocol.validateActionablePendingActions(previousActionsData, 10);

        assertEq(validated, 4, "validated actions");

        (PendingAction[] memory actions,) = protocol.getActionablePendingActions(address(this));
        assertEq(actions.length, 0, "remaining pending actions");
    }

    /**
     * @custom:scenario Validate pending actions manually with a limit on the number of validations
     * @custom:given A protocol with four pending actions (one of each type, all different users)
     * @custom:when The actions are validated manually with the correct calldata
     * @custom:and a maxValidations of 2
     * @custom:then The first two actions are validated and the returned count is 2
     * @custom:and the validated pending actions are removed but two are remaining
     */
    function test_validateActionablePendingActionsLimit() public {
        PreviousActionsData memory previousActionsData = _setUpFourPendingActions();

        uint256 validated = protocol.validateActionablePendingActions(previousActionsData, 2);

        assertEq(validated, 2, "validated actions");

        (PendingAction[] memory actions,) = protocol.getActionablePendingActions(address(this));
        assertEq(actions.length, 2, "remaining pending actions");
    }

    /**
     * @custom:scenario Validate pending actions when there is none
     * @custom:given A protocol with no pending actions
     * @custom:when The actions are validated manually
     * @custom:then No actions are validated and the returned count is 0
     */
    function test_validateActionablePendingActionsNone() public {
        uint256 validated = protocol.validateActionablePendingActions(EMPTY_PREVIOUS_DATA, 10);

        assertEq(validated, 0, "validated actions");
    }

    /**
     * @custom:scenario Validate pending actions with bad data
     * @custom:given A protocol with four pending actions (one of each type, all different users)
     * @custom:when The actions are validated manually with bad calldata (the last raw index is invalid)
     * @custom:then The first three actions are validated and the returned count is 3
     * @custom:and the validated pending actions are removed but one is remaining
     */
    function test_validateActionablePendingActionsBadIndex() public {
        PreviousActionsData memory previousActionsData = _setUpFourPendingActions();
        previousActionsData.rawIndices[3] = 42; // simulate bad data for last pending action

        uint256 validated = protocol.validateActionablePendingActions(previousActionsData, 10);

        assertEq(validated, 3, "validated actions");

        (PendingAction[] memory actions,) = protocol.getActionablePendingActions(address(this));
        assertEq(actions.length, 1, "remaining pending actions");
    }

    /**
     * @custom:scenario Validate pending actions with bad data
     * @custom:given A protocol with four pending actions (one of each type, all different users)
     * @custom:when The actions are validated manually with bad calldata (there is a mismatch in the price data length)
     * @custom:then No pending action is validated and the returned count is 0
     */
    function test_validateActionablePendingActionsBadDataLength() public {
        PreviousActionsData memory previousActionsData = _setUpFourPendingActions();
        previousActionsData.priceData = new bytes[](2); // simulate bad data
        previousActionsData.priceData[0] = abi.encode(params.initialPrice);
        previousActionsData.priceData[1] = previousActionsData.priceData[0];

        uint256 validated = protocol.validateActionablePendingActions(previousActionsData, 10);

        assertEq(validated, 0, "validated actions");
    }

    /**
     * @custom:scenario Validate pending actions with an empty first calldata item
     * @custom:given A protocol with four pending actions (one of each type, all different users)
     * @custom:when The actions are validated manually with an empty first calldata item and 3 non-empty calldata items
     * @custom:then The first three actions are validated and the returned count is 3
     */
    function test_validateActionablePendingActionsSkipFirst() public {
        PreviousActionsData memory previousActionsData = _setUpFourPendingActions();
        // add empty item at the beginning of the calldata
        bytes[] memory priceData = new bytes[](4);
        priceData[0] = "";
        priceData[1] = previousActionsData.priceData[0];
        priceData[2] = previousActionsData.priceData[1];
        priceData[3] = previousActionsData.priceData[2];
        previousActionsData.priceData = priceData;
        uint128[] memory rawIndices = new uint128[](4);
        // wrap around if necessary to keep the rawIndices list contiguous
        unchecked {
            rawIndices[0] = previousActionsData.rawIndices[0] - 1;
        }
        rawIndices[1] = previousActionsData.rawIndices[0];
        rawIndices[2] = previousActionsData.rawIndices[1];
        rawIndices[3] = previousActionsData.rawIndices[2];
        previousActionsData.rawIndices = rawIndices;

        uint256 validated = protocol.validateActionablePendingActions(previousActionsData, 10);

        assertEq(validated, 3, "validated actions");
    }

    /**
     * @custom:scenario The user sends too much ether when validating pending actions
     * @custom:given A protocol with four pending actions (one of each type, all different users)
     * @custom:when The user sends 0.5 ether as value in the `validateActionablePendingActions` call
     * @custom:then The user gets refunded the excess ether (0.5 ether - validationCost * 4)
     */
    function test_validateActionablePendingActionsEtherRefund() public {
        PreviousActionsData memory previousActionsData = _setUpFourPendingActions();
        oracleMiddleware.setRequireValidationCost(true); // require 1 wei per validation
        uint256 validationCost =
            oracleMiddleware.validationCost(previousActionsData.priceData[0], ProtocolAction.ValidateOpenPosition);
        validationCost +=
            oracleMiddleware.validationCost(previousActionsData.priceData[1], ProtocolAction.ValidateClosePosition);
        validationCost +=
            oracleMiddleware.validationCost(previousActionsData.priceData[2], ProtocolAction.ValidateDeposit);
        validationCost +=
            oracleMiddleware.validationCost(previousActionsData.priceData[3], ProtocolAction.ValidateWithdrawal);
        assertEq(validationCost, 4, "validation cost");
        uint256 balanceBefore = address(this).balance;
        protocol.validateActionablePendingActions{ value: 0.5 ether }(previousActionsData, 10);
        assertEq(address(this).balance, balanceBefore - validationCost, "user balance after refund");
    }

    /**
     * @dev Set up four pending actions (one of each type, all different users) and return the previous actions data
     * @return previousActionsData_ The previous actions data, all with the same price as the initial price
     */
    function _setUpFourPendingActions() internal returns (PreviousActionsData memory previousActionsData_) {
        setUpUserPositionInLong(
            USER_1, ProtocolAction.InitiateOpenPosition, 1 ether, params.initialPrice / 2, params.initialPrice
        );
        setUpUserPositionInLong(
            USER_2, ProtocolAction.InitiateClosePosition, 1 ether, params.initialPrice / 2, params.initialPrice
        );
        setUpUserPositionInVault(USER_3, ProtocolAction.InitiateDeposit, 1 ether, params.initialPrice);
        setUpUserPositionInVault(USER_4, ProtocolAction.InitiateWithdrawal, 1 ether, params.initialPrice);
        // make actionable
        skip(protocol.getValidationDeadline() + 1);

        (PendingAction[] memory actions, uint128[] memory rawIndices) =
            protocol.getActionablePendingActions(address(this));

        assertEq(actions.length, 4, "actions length");

        bytes[] memory priceData = new bytes[](4);
        priceData[0] = abi.encode(params.initialPrice);
        priceData[1] = priceData[0];
        priceData[2] = priceData[0];
        priceData[3] = priceData[0];
        previousActionsData_ = PreviousActionsData({ priceData: priceData, rawIndices: rawIndices });
    }

    // test refunds
    receive() external payable { }
}

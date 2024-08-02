// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { USER_1, USER_2 } from "../../../utils/Constants.sol";
import { UsdnProtocolBaseFixture } from "../utils/Fixtures.sol";

/**
 * @custom:feature Test the `_createOpenPendingAction` internal function of the actions utils layer
 * @custom:background An initialized protocol with default parameters
 * @custom:and The security deposit setting enabled
 */
contract TestUsdnProtocolActionsCreateOpenPendingAction is UsdnProtocolBaseFixture {
    InitiateOpenPositionData data;

    function setUp() public {
        params = DEFAULT_PARAMS;
        params.flags.enableSecurityDeposit = true;
        _setUp(params);

        data.posId.tick = 42 * _tickSpacing;
        data.posId.tickVersion = 1;
        data.posId.index = 2;
    }

    /**
     * @custom:scenario An open pending action is created
     * @custom:given USER_1 being the `to` address
     * @custom:and USER_2 being the `validator` address
     * @custom:when _createOpenPendingAction is called
     * @custom:then the amount to refund should be 0
     * @custom:and the create pending action's data should match the inputs
     */
    function test_createOpenPendingAction() public {
        uint64 securityDeposit = 0.5 ether;

        uint256 amountToRefund = protocol.i_createOpenPendingAction(USER_1, USER_2, securityDeposit, data);

        assertEq(amountToRefund, 0, "Amount to refund should be 0");

        (PendingAction memory pendingAction,) = protocol.i_getPendingAction(USER_2);
        assertEq(
            uint8(pendingAction.action),
            uint8(ProtocolAction.ValidateOpenPosition),
            "action type should be ValidateOpenPosition"
        );
        assertEq(pendingAction.timestamp, uint40(block.timestamp), "timestamp should be now");
        assertEq(pendingAction.to, USER_1, "USER_1 should be the `to` address");
        assertEq(pendingAction.validator, USER_2, "USER_2 should be the `validator` address");
        assertEq(
            pendingAction.securityDepositValue, securityDeposit, "securityDepositValue should be the provided amount"
        );
        assertEq(pendingAction.var1, data.posId.tick, "var1 should be the tick of the provided position");
        assertEq(pendingAction.var2, 0, "var2 should be 0");
        assertEq(pendingAction.var3, 0, "var3 should be 0");
        assertEq(pendingAction.var4, data.posId.tickVersion, "var4 should be the tick version of the provided position");
        assertEq(pendingAction.var5, data.posId.index, "var5 should be the index of the provided position");
        assertEq(pendingAction.var6, 0, "var6 should be 0");
        assertEq(pendingAction.var7, 0, "var7 should be 0");
    }

    /**
     * @custom:scenario A stale pending action is removed so an amount to refund is returned
     * @custom:given A stale pending action exists for the user
     * @custom:when _createOpenPendingAction is called
     * @custom:then the amount to refund should be the security deposit value
     */
    function test_createOpenPendingActionWithStaleAction() public {
        _createStalePendingActionHelper();

        uint64 securityDeposit = protocol.getSecurityDepositValue();
        uint256 amountToRefund = protocol.i_createOpenPendingAction(address(this), address(this), securityDeposit, data);

        assertEq(amountToRefund, securityDeposit, "Amount to refund should be the security deposit value");
    }
}

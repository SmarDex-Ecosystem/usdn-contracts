// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { USER_1, USER_2 } from "../../../utils/Constants.sol";
import { UsdnProtocolBaseFixture } from "../utils/Fixtures.sol";

/**
 * @custom:feature Test the `_createClosePendingAction` internal function of the actions utils layer
 * @custom:background An initialized protocol with default parameters
 * @custom:and The security deposit setting enabled
 */
contract TestUsdnProtocolActionsCreateClosePendingAction is UsdnProtocolBaseFixture {
    /// @dev Instance of ClosePositionData to store data for closing positions
    ClosePositionData data;

    function setUp() public {
        params = DEFAULT_PARAMS;
        params.flags.enableSecurityDeposit = true;
        _setUp(params);

        data.lastPrice = DEFAULT_PARAMS.initialPrice * 11 / 10; // 10% price increase
        data.longTradingExpo = uint256(protocol.getLongTradingExpo(data.lastPrice));
        data.liqMulAcc = protocol.getLiqMultiplierAccumulator();
    }

    /**
     * @custom:scenario A close position pending action is created
     * @custom:given USER_1 being the `to` address
     * @custom:and USER_2 being the `validator` address
     * @custom:and the price has increased by 10%
     * @custom:when _createClosePendingAction is called
     * @custom:then the amount to refund should be 0
     * @custom:and the created pending action's data should match the inputs
     */
    function test_createClosePendingAction() public {
        uint128 amountToClose = DEFAULT_PARAMS.initialLong / 2;
        data.totalExpoToClose = amountToClose * 2;
        data.tempPositionValue = uint256(amountToClose) * data.lastPrice / DEFAULT_PARAMS.initialPrice;
        uint64 securityDeposit = 0.5 ether;

        uint256 amountToRefund =
            protocol.i_createClosePendingAction(USER_1, USER_2, initialPosition, amountToClose, securityDeposit, data);

        uint256 multiplier =
            protocol.i_calcFixedPrecisionMultiplier(data.lastPrice, data.longTradingExpo, data.liqMulAcc);
        assertEq(amountToRefund, 0, "Amount to refund should be 0");

        (PendingAction memory pendingAction,) = protocol.i_getPendingAction(USER_2);
        assertEq(
            uint8(pendingAction.action),
            uint8(ProtocolAction.ValidateClosePosition),
            "action type should be ValidateClosePosition"
        );
        assertEq(pendingAction.timestamp, uint40(block.timestamp), "timestamp should be now");
        assertEq(pendingAction.to, USER_1, "USER_1 should be the to address");
        assertEq(pendingAction.validator, USER_2, "USER_2 should be the validator address");
        assertEq(
            pendingAction.securityDepositValue, securityDeposit, "securityDepositValue should be the provided amount"
        );
        assertEq(pendingAction.var1, initialPosition.tick, "var1 should be the tick of the provided position");
        assertEq(pendingAction.var2, amountToClose, "var2 should be the amount to close");
        assertEq(pendingAction.var3, data.totalExpoToClose, "var3 should be the total expo to close");
        assertEq(
            pendingAction.var4, initialPosition.tickVersion, "var4 should be the tick version of the provided position"
        );
        assertEq(pendingAction.var5, initialPosition.index, "var5 should be the index of the provided position");
        assertEq(pendingAction.var6, multiplier, "var6 should be the multiplier");
        assertEq(pendingAction.var7, data.tempPositionValue, "var7 should be the value of the amount to close");
    }

    /**
     * @custom:scenario A stale pending action is removed so an amount to refund is returned
     * @custom:given A stale pending action exists for the user
     * @custom:when _createClosePendingAction is called
     * @custom:then the amount to refund should be the security deposit value
     */
    function test_createClosePendingActionWithStaleAction() public {
        _createStalePendingActionHelper();

        uint128 amountToClose = DEFAULT_PARAMS.initialLong / 2;
        data.totalExpoToClose = amountToClose * 2;
        data.lastPrice = DEFAULT_PARAMS.initialPrice;
        data.tempPositionValue = amountToClose;
        uint64 securityDeposit = protocol.getSecurityDepositValue();

        uint256 amountToRefund = protocol.i_createClosePendingAction(
            address(this), address(this), initialPosition, amountToClose, securityDeposit, data
        );

        assertEq(amountToRefund, securityDeposit, "Amount to refund should be the security deposit value");
    }
}

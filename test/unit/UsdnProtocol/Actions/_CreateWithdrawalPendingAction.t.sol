// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { USER_1, USER_2 } from "../../../utils/Constants.sol";
import { UsdnProtocolBaseFixture } from "../utils/Fixtures.sol";

import { UsdnProtocolActionsVaultLibrary as ActionsVault } from
    "../../../../src/UsdnProtocol/libraries/UsdnProtocolActionsVaultLibrary.sol";

/**
 * @custom:feature Test the `_createWithdrawalPendingAction` internal function of the actions vault layer
 * @custom:background An initialized protocol with default parameters
 * @custom:and The security deposit setting enabled
 */
contract TestUsdnProtocolActionsCreateWithdrawalPendingAction is UsdnProtocolBaseFixture {
    /// @dev Instance of WithdrawalData to store data for withdrawing assets
    ActionsVault.WithdrawalData data;
    /// @dev The amount of USDN shares originally deposited
    uint152 usdnShares = 1 ether;

    function setUp() public {
        params = DEFAULT_PARAMS;
        params.flags.enableSecurityDeposit = true;
        _setUp(params);

        data.feeBps = protocol.getVaultFeeBps();
        data.totalExpo = 420 ether;
        data.balanceVault = 41 ether;
        data.balanceLong = 42 ether;
        data.usdnTotalShares = 100_000 * (10 ** protocol.TOKENS_DECIMALS());
    }

    /**
     * @custom:scenario A withdrawal pending action is created
     * @custom:given USER_1 being the `to` address
     * @custom:and USER_2 being the `validator` address
     * @custom:when _createWithdrawalPendingAction is called
     * @custom:then the amount to refund should be 0
     * @custom:and the created pending action's data should match the inputs
     */
    function test_createWithdrawalPendingAction() public {
        uint64 securityDeposit = 0.5 ether;
        uint24 sharesLSB = protocol.i_calcWithdrawalAmountLSB(usdnShares);
        uint128 sharesMSB = protocol.i_calcWithdrawalAmountMSB(usdnShares);

        uint256 amountToRefund =
            protocol.i_createWithdrawalPendingAction(USER_1, USER_2, usdnShares, securityDeposit, data);

        assertEq(amountToRefund, 0, "Amount to refund should be 0");

        (PendingAction memory pendingAction,) = protocol.i_getPendingAction(USER_2);
        assertEq(
            uint8(pendingAction.action),
            uint8(ProtocolAction.ValidateWithdrawal),
            "action type should be ValidateWithdrawal"
        );
        assertEq(pendingAction.timestamp, uint40(block.timestamp), "timestamp should be now");
        assertEq(pendingAction.to, USER_1, "USER_1 should be the to address");
        assertEq(pendingAction.validator, USER_2, "USER_2 should be the validator address");
        assertEq(
            pendingAction.securityDepositValue, securityDeposit, "securityDepositValue should be the provided amount"
        );
        assertEq(uint24(pendingAction.var1), sharesLSB, "var1 should be equal to the calculated sharesLSB");
        assertEq(pendingAction.var2, sharesMSB, "var2 should be equal to the calculated sharesMSB");
        assertEq(pendingAction.var3, data.feeBps, "var3 should be the fee");
        assertEq(pendingAction.var4, data.totalExpo, "var4 should be the provided total expo");
        assertEq(pendingAction.var5, data.balanceVault, "var5 should be the provided balance of the vault side");
        assertEq(pendingAction.var6, data.balanceLong, "var6 should be the provided balance of the long side");
        assertEq(pendingAction.var7, data.usdnTotalShares, "var7 should be the provided total supply of shares");
    }

    /**
     * @custom:scenario A stale pending action is removed so an amount to refund is returned
     * @custom:given A stale pending action exists for the user
     * @custom:when _createWithdrawalPendingAction is called
     * @custom:then the amount to refund should be the security deposit value
     */
    function test_createWithdrawalPendingActionWithStaleAction() public {
        _createStalePendingActionHelper();

        uint64 securityDeposit = protocol.getSecurityDepositValue();

        uint256 amountToRefund =
            protocol.i_createWithdrawalPendingAction(address(this), address(this), usdnShares, securityDeposit, data);

        assertEq(amountToRefund, securityDeposit, "Amount to refund should be the security deposit value");
    }
}

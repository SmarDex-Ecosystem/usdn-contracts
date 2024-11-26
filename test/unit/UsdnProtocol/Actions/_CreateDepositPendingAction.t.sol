// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { USER_1, USER_2 } from "../../../utils/Constants.sol";
import { UsdnProtocolBaseFixture } from "../utils/Fixtures.sol";

import { UsdnProtocolConstantsLibrary as Constants } from
    "../../../../src/UsdnProtocol/libraries/UsdnProtocolConstantsLibrary.sol";
import { UsdnProtocolVaultLibrary as Vault } from "../../../../src/UsdnProtocol/libraries/UsdnProtocolVaultLibrary.sol";

/**
 * @custom:feature Test the `_createDepositPendingAction` internal function of the actions vault layer
 * @custom:background An initialized protocol with default parameters
 * @custom:and The security deposit setting enabled
 */
contract TestUsdnProtocolActionsCreateDepositPendingAction is UsdnProtocolBaseFixture {
    /// @dev Instance of InitiateDepositData to store data for depositing assets
    Vault.InitiateDepositData data;
    /// @dev The amount of assets to deposit
    uint128 amount = 1 ether;

    function setUp() public {
        params = DEFAULT_PARAMS;
        params.flags.enableSecurityDeposit = true;
        _setUp(params);

        data.lastPrice = params.initialPrice;
        data.totalExpo = 420 ether;
        data.balanceVault = 41 ether;
        data.balanceLong = 42 ether;
        data.usdnTotalShares = 100_000 * (10 ** Constants.TOKENS_DECIMALS);
    }

    /**
     * @custom:scenario A deposit pending action is created
     * @custom:and USER_1 being the `to` address
     * @custom:given USER_2 being the `validator` address
     * @custom:when _createDepositPendingAction is called
     * @custom:then the amount to refund should be 0
     * @custom:and the created pending action's data should match the inputs
     */
    function test_createDepositPendingAction() public {
        uint64 securityDeposit = 0.5 ether;

        uint256 amountToRefund = protocol.i_createDepositPendingAction(USER_1, USER_2, securityDeposit, amount, data);

        assertEq(amountToRefund, 0, "Amount to refund should be 0");

        (PendingAction memory pendingAction,) = protocol.i_getPendingAction(USER_2);
        assertEq(
            uint8(pendingAction.action), uint8(ProtocolAction.ValidateDeposit), "action type should be ValidateDeposit"
        );
        assertEq(pendingAction.timestamp, uint40(block.timestamp), "timestamp should be now");
        assertEq(pendingAction.to, USER_1, "USER_1 should be the `to` address");
        assertEq(pendingAction.validator, USER_2, "USER_2 should be the `validator` address");
        assertEq(
            pendingAction.securityDepositValue, securityDeposit, "securityDepositValue should be the provided amount"
        );
        assertEq(pendingAction.var0, protocol.getVaultFeeBps(), "var0 should be the vault fee");
        assertEq(pendingAction.var2, amount, "var2 should be the amount");
        assertEq(pendingAction.var3, data.lastPrice, "var3 should be the last price");
        assertEq(pendingAction.var4, data.totalExpo, "var4 should be the totalExpo attribute of `data`");
        assertEq(pendingAction.var5, data.balanceVault, "var5 should be the balanceVault attribute of `data`");
        assertEq(pendingAction.var6, data.balanceLong, "var6 should be the balanceLong attribute of `data`");
        assertEq(pendingAction.var7, data.usdnTotalShares, "var7 should be the usdnTotalShares attribute of `data`");
    }

    /**
     * @custom:scenario A stale pending action is removed so an amount to refund is returned
     * @custom:given A stale pending action exists for the user
     * @custom:when _createDepositPendingAction is called
     * @custom:then The amount to refund should be the security deposit value
     */
    function test_createDepositPendingActionWithStaleAction() public {
        _createStalePendingActionHelper();

        uint64 securityDeposit = protocol.getSecurityDepositValue();
        uint256 amountToRefund =
            protocol.i_createDepositPendingAction(address(this), address(this), securityDeposit, amount, data);

        assertEq(amountToRefund, securityDeposit, "Amount to refund should be the security deposit value");
    }
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import { ADMIN } from "../../../utils/Constants.sol";
import { UsdnProtocolBaseFixture } from "../utils/Fixtures.sol";

import { UsdnProtocolActionsVaultLibrary as ActionsVault } from
    "../../../../src/UsdnProtocol/libraries/UsdnProtocolActionsVaultLibrary.sol";

/**
 * @custom:feature Test of the protocol `_prepareWithdrawalData` internal function
 * @custom:background A user deposited assets in the protocol and minted USDN tokens
 */
contract TestUsdnProtocolActionsPrepareWithdrawalData is UsdnProtocolBaseFixture {
    uint128 private constant DEPOSITED_AMOUNT = 1 ether;
    uint152 private usdnSharesAmount;
    bytes private currentPriceData;

    function setUp() public {
        super._setUp(DEFAULT_PARAMS);

        currentPriceData = abi.encode(params.initialPrice);

        setUpUserPositionInVault(
            address(this), ProtocolAction.ValidateDeposit, DEPOSITED_AMOUNT, DEFAULT_PARAMS.initialPrice
        );
        usdnSharesAmount = uint152(usdn.sharesOf(address(this)));
    }

    /**
     * @custom:scenario _prepareWithdrawalData is called with the amount of shares the current user has
     * @custom:when _prepareWithdrawalData is called
     * @custom:then The matching data is returned
     * @custom:and There should be no pending liquidations
     */
    function test_prepareWithdrawalData() public {
        ActionsVault.WithdrawalData memory data =
            protocol.i_prepareWithdrawalData(address(this), usdnSharesAmount, currentPriceData);

        assertFalse(data.isLiquidationPending, "There should be no pending liquidations");
        _assertData(data, false);
    }

    /**
     * @custom:scenario _prepareWithdrawalData is called with 2 ticks that can be liquidated
     * @custom:given A current price below the second tick's liquidation price
     * @custom:and A high risk position that will be liquidated first
     * @custom:and A liquidation iterations setting at 1
     * @custom:when _prepareWithdrawalData is called
     * @custom:then The matching data is returned
     * @custom:and Only the high risk position should have been liquidated
     * @custom:and The function should have returned early
     * @custom:and There should be pending liquidations
     */
    function test_prepareWithdrawalDataWithPendingLiquidations() public {
        // open long positions to liquidate
        setUpUserPositionInLong(
            OpenParams({
                user: address(this),
                untilAction: ProtocolAction.ValidateOpenPosition,
                positionSize: DEPOSITED_AMOUNT,
                desiredLiqPrice: params.initialPrice * 9 / 10, // 10x leverage
                price: params.initialPrice
            })
        );
        setUpUserPositionInLong(
            OpenParams({
                user: address(this),
                untilAction: ProtocolAction.ValidateOpenPosition,
                positionSize: DEPOSITED_AMOUNT,
                desiredLiqPrice: params.initialPrice * 8 / 10, // 9x leverage
                price: params.initialPrice
            })
        );
        skip(30 minutes);

        vm.prank(ADMIN);
        protocol.setLiquidationIteration(1);

        currentPriceData = abi.encode(params.initialPrice * 7 / 10);

        ActionsVault.WithdrawalData memory data =
            protocol.i_prepareWithdrawalData(address(this), usdnSharesAmount, currentPriceData);

        assertTrue(data.isLiquidationPending, "There should be pending liquidations");
        _assertData(data, true);
    }

    /// @notice Assert the data in WithdrawalData depending on `isEarlyReturn`
    function _assertData(ActionsVault.WithdrawalData memory data, bool isEarlyReturn) private {
        uint128 currentPrice = abi.decode(currentPriceData, (uint128));

        if (isEarlyReturn) {
            assertEq(data.pendingActionPrice, 0, "The pending action price should not be set");
            assertEq(data.usdnTotalShares, 0, "The total shares of USDN should not be set");
            assertEq(data.totalExpo, 0, "The total expo should not be set");
            assertEq(data.balanceLong, 0, "The balance long should not be set");
            assertEq(data.balanceVault, 0, "The balance vault should not be set");
            assertEq(data.withdrawalAmount, 0, "The amount withdrawn should not be set");
        } else {
            assertEq(data.pendingActionPrice, currentPrice, "The pending action price should be the current price");
            assertEq(
                data.usdnTotalShares, usdn.totalShares(), "The total shares of USDN should be the one in the contract"
            );
            assertEq(data.totalExpo, protocol.getTotalExpo(), "The total expo should be the one in the protocol");
            assertEq(data.balanceLong, protocol.getBalanceLong(), "The balance long should be the one in the protocol");
            assertEq(
                data.balanceVault, protocol.getBalanceVault(), "The balance vault should be the one in the protocol"
            );
            assertEq(data.withdrawalAmount, DEPOSITED_AMOUNT, "The amount withdrawn be the amount deposited");
        }
    }
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { USER_1 } from "../../utils/Constants.sol";
import { RebalancerFixture } from "./utils/Fixtures.sol";

import { IUsdnProtocolTypes as Types } from "../../../src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";

/**
 * @custom:feature The `validateDepositAssets` function of the rebalancer contract
 * @custom:background Given the user initiated a deposit into the contract
 */
contract TestRebalancerValidateDepositAssets is RebalancerFixture {
    uint88 constant INITIAL_DEPOSIT = 2 ether;

    function setUp() public {
        super._setUp();

        wstETH.mintAndApprove(address(this), 10_000 ether, address(rebalancer), type(uint256).max);
        rebalancer.initiateDepositAssets(INITIAL_DEPOSIT, address(this));
    }

    /**
     * @custom:scenario The user validates a deposit
     * @custom:when The user validates the deposit
     * @custom:then The user deposit is updated with the position version
     * @custom:and The user deposit timestamp is set to zero
     * @custom:and The pending assets amount is updated
     * @custom:and The correct event is emitted
     */
    function test_validateDeposit() public {
        skip(rebalancer.getTimeLimits().validationDelay);

        uint256 expectedVersion = rebalancer.getPositionVersion() + 1;
        uint256 initialPending = rebalancer.getPendingAssetsAmount();

        vm.expectEmit();
        emit AssetsDeposited(address(this), INITIAL_DEPOSIT, expectedVersion);
        rebalancer.validateDepositAssets();

        UserDeposit memory userDeposit = rebalancer.getUserDepositData(address(this));
        assertEq(userDeposit.entryPositionVersion, expectedVersion, "deposit pos version");
        assertEq(userDeposit.amount, INITIAL_DEPOSIT, "deposit amount");
        assertEq(userDeposit.initiateTimestamp, 0, "deposit timestamp");

        assertEq(rebalancer.getPendingAssetsAmount(), initialPending + INITIAL_DEPOSIT, "pending assets");
    }

    /**
     * @custom:scenario The user tries to validate a deposit that has already been validated
     * @custom:when The user tries to validate the deposit again
     * @custom:then The call reverts with a {RebalancerNoPendingAction} error
     */
    function test_RevertWhen_validateDepositAlreadyValidated() public {
        skip(rebalancer.getTimeLimits().validationDelay);
        rebalancer.validateDepositAssets();

        vm.expectRevert(RebalancerNoPendingAction.selector);
        rebalancer.validateDepositAssets();
    }

    /**
     * @custom:scenario The user tries to validate when not in Rebalancer
     * @custom:when The user tries to validate a deposit but they are not in the Rebalancer
     * @custom:then The call reverts with a {RebalancerNoPendingAction} error
     */
    function test_RevertWhen_validateDepositNotInRebalancer() public {
        vm.expectRevert(RebalancerNoPendingAction.selector);
        vm.prank(USER_1);
        rebalancer.validateDepositAssets();
    }

    /**
     * @custom:scenario The user tries to validate a deposit too soon
     * @custom:when The user tries to validate the deposit before the validation delay
     * @custom:then The call reverts with a RebalancerValidateTooEarly error
     */
    function test_RevertWhen_validateDepositTooSoon() public {
        skip(rebalancer.getTimeLimits().validationDelay - 1);
        vm.expectRevert(RebalancerValidateTooEarly.selector);
        rebalancer.validateDepositAssets();
    }

    /**
     * @custom:scenario The user tries to validate a deposit too late
     * @custom:when The user tries to validate the deposit after the validation deadline
     * @custom:then The call reverts with a RebalancerActionCooldown error
     */
    function test_RevertWhen_validateDepositTooLate() public {
        skip(rebalancer.getTimeLimits().validationDeadline + 1);
        vm.expectRevert(RebalancerActionCooldown.selector);
        rebalancer.validateDepositAssets();
    }

    /**
     * @custom:scenario The user tries to validate a deposit when included in a position
     * @custom:when The user tries to validate the deposit after being included in a position
     * @custom:then The call reverts with a {RebalancerNoPendingAction} error
     */
    function test_RevertWhen_validateDepositWhenIncludedInPosition() public {
        skip(rebalancer.getTimeLimits().validationDelay);
        rebalancer.validateDepositAssets();

        vm.prank(address(usdnProtocol));
        rebalancer.updatePosition(Types.PositionId(0, 0, 0), 0);

        vm.expectRevert(RebalancerNoPendingAction.selector);
        rebalancer.validateDepositAssets();
    }

    /**
     * @custom:scenario The user tries to validate a deposit but is in a position that got liquidated
     * @custom:when The user tries to validate the deposit after being liquidated
     * @custom:then The call reverts with a {RebalancerNoPendingAction} error
     */
    function test_RevertWhen_validateDepositWhenInLiquidatedPosition() public {
        skip(rebalancer.getTimeLimits().validationDelay);
        rebalancer.validateDepositAssets();

        vm.prank(address(usdnProtocol));
        rebalancer.notifyPositionLiquidated();

        vm.expectRevert(RebalancerNoPendingAction.selector);
        rebalancer.validateDepositAssets();
    }

    /**
     * @custom:scenario The user tries to validate a deposit but has a pending withdrawal
     * @custom:when The user tries to validate the deposit after initiating a withdrawal
     * @custom:or The user tries to validate the deposit after the validation delay
     * @custom:or The user tries to validate the deposit after the action cooldown
     * @custom:then The call reverts with a {RebalancerDepositUnauthorized} error
     */
    function test_RevertWhen_validateDepositPendingWithdrawal() public {
        skip(rebalancer.getTimeLimits().validationDelay);
        rebalancer.validateDepositAssets();
        rebalancer.initiateWithdrawAssets();

        vm.expectRevert(RebalancerDepositUnauthorized.selector);
        rebalancer.validateDepositAssets();

        skip(rebalancer.getTimeLimits().validationDelay);

        vm.expectRevert(RebalancerDepositUnauthorized.selector);
        rebalancer.validateDepositAssets();

        skip(rebalancer.getTimeLimits().actionCooldown);

        vm.expectRevert(RebalancerDepositUnauthorized.selector);
        rebalancer.validateDepositAssets();
    }
}

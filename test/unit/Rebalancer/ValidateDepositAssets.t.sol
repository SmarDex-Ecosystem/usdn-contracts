// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import { USER_1 } from "../../utils/Constants.sol";
import { RebalancerFixture } from "./utils/Fixtures.sol";

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
     * @custom:then The call reverts with a RebalancerActionWasValidated error
     */
    function test_RevertWhen_validateDepositAlreadyValidated() public {
        skip(rebalancer.getTimeLimits().validationDelay);
        rebalancer.validateDepositAssets();

        vm.expectRevert(RebalancerActionWasValidated.selector);
        rebalancer.validateDepositAssets();
    }

    /**
     * @custom:scenario The user tries to validate a deposit that has not been initiated
     * @custom:when The user tries to validate a deposit that has not been initiated
     * @custom:then The call reverts with a RebalancerActionWasValidated error
     */
    function test_RevertWhen_validateDepositNotInitiated() public {
        vm.expectRevert(RebalancerActionWasValidated.selector);
        vm.prank(USER_1);
        rebalancer.validateDepositAssets();
    }

    function test_RevertWhen_validateDepositUnvalidatedWithdrawal() public {
        // TODO
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
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { USER_1 } from "../../utils/Constants.sol";
import { RebalancerFixture } from "./utils/Fixtures.sol";

import { IUsdnProtocolTypes as Types } from "../../../src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";

/**
 * @custom:feature The `resetDepositAssets` function of the rebalancer contract
 * @custom:background Given the user has not interacted with the Rebalancer
 */
contract TestRebalancerResetDepositAssets is RebalancerFixture {
    uint88 constant INITIAL_DEPOSIT = 2 ether;

    function setUp() public {
        super._setUp();

        wstETH.mintAndApprove(address(this), 10_000 ether, address(rebalancer), type(uint256).max);
        wstETH.mintAndApprove(USER_1, 10_000 ether, address(rebalancer), type(uint256).max);
    }

    /**
     * @custom:scenario The user resets his deposit
     * @custom:given The user initiated a deposit and waited too long to validate it
     * @custom:and The user initiated a deposit and waited for the cooldown
     * @custom:when The user resets his deposit
     * @custom:then The user gets the assets back
     * @custom:and The user deposit data is reset
     * @custom:and The correct event is emitted
     */
    function test_resetDeposit() public {
        rebalancer.initiateDepositAssets(INITIAL_DEPOSIT, address(this));
        // wait past the cooldown
        skip(rebalancer.getTimeLimits().actionCooldown);
        uint256 balanceBefore = wstETH.balanceOf(address(this));

        vm.expectEmit();
        emit DepositRefunded(address(this), INITIAL_DEPOSIT);
        rebalancer.resetDepositAssets();

        UserDeposit memory userDeposit = rebalancer.getUserDepositData(address(this));
        assertEq(userDeposit.entryPositionVersion, 0, "deposit pos version");
        assertEq(userDeposit.amount, 0, "deposit amount");
        assertEq(userDeposit.initiateTimestamp, 0, "deposit timestamp");

        assertEq(wstETH.balanceOf(address(this)), balanceBefore + INITIAL_DEPOSIT, "user balance");
    }

    /**
     * @custom:scenario The user tries to reset his deposit but was not in the Rebalancer
     * @custom:when The user tries to reset his deposit
     * @custom:then The call reverts with {RebalancerNoPendingAction}
     */
    function test_RevertWhen_resetDepositNotInRebalancer() public {
        vm.expectRevert(RebalancerNoPendingAction.selector);
        rebalancer.resetDepositAssets();
    }

    /**
     * @custom:scenario The user tries to reset his deposit too soon
     * @custom:given The user initiated a deposit and didn't wait for the cooldown
     * @custom:when The user tries to reset his deposit immediately
     * @custom:or The user tries to reset his deposit after the validation delay
     * @custom:or The user tries to reset his deposit just before the cooldown elapsed
     * @custom:then The call reverts with `RebalancerActionCooldown`
     */
    function test_RevertWhen_resetDepositTooSoon() public {
        rebalancer.initiateDepositAssets(INITIAL_DEPOSIT, address(this));

        vm.expectRevert(RebalancerActionCooldown.selector);
        rebalancer.resetDepositAssets();

        skip(rebalancer.getTimeLimits().validationDelay);

        vm.expectRevert(RebalancerActionCooldown.selector);
        rebalancer.resetDepositAssets();

        skip(rebalancer.getTimeLimits().actionCooldown - rebalancer.getTimeLimits().validationDelay - 1);

        vm.expectRevert(RebalancerActionCooldown.selector);
        rebalancer.resetDepositAssets();
    }

    function test_RevertWhen_resetDepositWhenUnincluded() public {
        rebalancer.initiateDepositAssets(INITIAL_DEPOSIT, address(this));
        skip(rebalancer.getTimeLimits().validationDelay);
        rebalancer.validateDepositAssets();

        vm.expectRevert(RebalancerNoPendingAction.selector);
        rebalancer.resetDepositAssets();
    }

    function test_RevertWhen_resetDepositWhenIncludedInPosition() public {
        rebalancer.initiateDepositAssets(INITIAL_DEPOSIT, address(this));
        skip(rebalancer.getTimeLimits().validationDelay);
        rebalancer.validateDepositAssets();

        vm.prank(address(usdnProtocol));
        rebalancer.updatePosition(Types.PositionId(0, 0, 0), 0);

        vm.expectRevert(RebalancerNoPendingAction.selector);
        rebalancer.resetDepositAssets();
    }

    /**
     * @custom:scenario The user tries to reset his deposit but has a pending withdrawal
     * @custom:given The user initiated and validated a deposit, then initiated a withdrawal
     * @custom:when The user tries to reset their deposit immediately
     * @custom:or The user tries to reset their deposit after the validation delay
     * @custom:or The user tries to reset their deposit after the cooldown elapsed
     * @custom:then The call reverts with {RebalancerActionNotValidated}
     */
    function test_RevertWhen_resetDepositWithPendingWithdrawal() public {
        rebalancer.initiateDepositAssets(INITIAL_DEPOSIT, address(this));
        skip(rebalancer.getTimeLimits().validationDelay);
        rebalancer.validateDepositAssets();
        rebalancer.initiateWithdrawAssets();

        vm.expectRevert(RebalancerActionNotValidated.selector);
        rebalancer.resetDepositAssets();

        skip(rebalancer.getTimeLimits().validationDelay);

        vm.expectRevert(RebalancerActionNotValidated.selector);
        rebalancer.resetDepositAssets();

        skip(rebalancer.getTimeLimits().actionCooldown);

        vm.expectRevert(RebalancerActionNotValidated.selector);
        rebalancer.resetDepositAssets();
    }
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import { RebalancerFixture } from "./utils/Fixtures.sol";
import { USER_1 } from "../../utils/Constants.sol";

/**
 * @custom:feature The `resetDepositAssets` function of the rebalancer contract
 * @custom:background Given the user initiated a deposit into the contract and waited too long
 */
contract TestRebalancerResetDepositAssets is RebalancerFixture {
    uint88 constant INITIAL_DEPOSIT = 2 ether;

    function setUp() public {
        super._setUp();

        wstETH.mintAndApprove(address(this), 10_000 ether, address(rebalancer), type(uint256).max);
        rebalancer.initiateDepositAssets(INITIAL_DEPOSIT, address(this));
        skip(rebalancer.getTimeLimits().validationDeadline + 1);
    }

    /**
     * @custom:scenario The user resets his deposit
     * @custom:given The user initiated a deposit and waited too long to validate it
     * @custom:and The user waited until the cooldown elapsed
     * @custom:when The user resets his deposit
     * @custom:then The user gets the assets back
     * @custom:and The user deposit data is reset
     * @custom:and The correct event is emitted
     */
    function test_resetDeposit() public {
        // wait past the cooldown (we already waited for `validationDeadline` in the setup)
        skip(rebalancer.getTimeLimits().actionCooldown - rebalancer.getTimeLimits().validationDeadline);
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
     * @custom:scenario The user tries to reset his deposit without having initiated one
     * @custom:given No deposit has been initiated
     * @custom:when The user tries to reset his deposit
     * @custom:then The call reverts with `RebalancerNoPendingAction`
     */
    function test_RevertWhen_resetDepositNoPendingAction() public {
        vm.expectRevert(RebalancerNoPendingAction.selector);
        vm.prank(USER_1);
        rebalancer.resetDepositAssets();
    }

    function test_RevertWhen_resetDepositWithPendingWithdrawal() public {
        // TODO
    }

    /**
     * @custom:scenario The user tries to reset his deposit too soon
     * @custom:given The user initiated a deposit and waited too long to validate it, but didn't wait for the cooldown
     * @custom:when The user tries to reset his deposit
     * @custom:then The call reverts with `RebalancerActionCooldown`
     */
    function test_RevertWhen_resetDepositTooSoon() public {
        vm.expectRevert(RebalancerActionCooldown.selector);
        rebalancer.resetDepositAssets();
    }
}

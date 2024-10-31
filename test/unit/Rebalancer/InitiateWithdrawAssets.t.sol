// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { IUsdnProtocolTypes as Types } from "../../../src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import { USER_1 } from "../../utils/Constants.sol";
import { RebalancerFixture } from "./utils/Fixtures.sol";

/**
 * @custom:feature The `initiateWithdrawAssets` function of the rebalancer contract
 * @custom:background Given a user has made and validated a deposit which was not yet included in the protocol
 */
contract TestRebalancerInitiateWithdrawAssets is RebalancerFixture {
    uint88 constant INITIAL_DEPOSIT = 3 ether;

    UserDeposit initialUserDeposit;
    uint128 initialPendingAssets;

    function setUp() public {
        super._setUp();

        wstETH.mintAndApprove(address(this), 10_000 ether, address(rebalancer), type(uint256).max);
        wstETH.mintAndApprove(USER_1, 10_000 ether, address(rebalancer), type(uint256).max);

        rebalancer.initiateDepositAssets(INITIAL_DEPOSIT, address(this));
        skip(rebalancer.getTimeLimits().validationDelay);
        rebalancer.validateDepositAssets();

        initialUserDeposit = rebalancer.getUserDepositData(address(this));
        initialPendingAssets = rebalancer.getPendingAssetsAmount();
    }

    function test_setUp() public view {
        assertGe(INITIAL_DEPOSIT, rebalancer.getMinAssetDeposit());
    }

    /**
     * @custom:scenario The user initiates a withdrawal of their unincluded assets
     * @custom:when The user initiates a withdrawal of their unincluded assets
     * @custom:then The initiateTimestamp of the user deposit is set to the current block timestamp
     * @custom:and The {InitiatedAssetsWithdrawal} event is emitted
     * @custom:and The rest of the state remains unchanged
     */
    function test_initiateWithdrawal() public {
        vm.expectEmit();
        emit InitiatedAssetsWithdrawal(address(this));
        rebalancer.initiateWithdrawAssets();

        UserDeposit memory userDeposit = rebalancer.getUserDepositData(address(this));
        assertEq(userDeposit.initiateTimestamp, block.timestamp, "initiate timestamp");
        assertEq(userDeposit.entryPositionVersion, initialUserDeposit.entryPositionVersion, "entry position version");
        assertEq(userDeposit.amount, initialUserDeposit.amount, "deposit amount");

        assertEq(rebalancer.getPendingAssetsAmount(), initialPendingAssets, "pending assets amount");
    }

    /**
     * @custom:scenario The user initiates a withdrawal after a pending withdrawal cooldown
     * @custom:given The user had initiated a withdrawal but didn't validate in time
     * @custom:and The cooldown period has passed
     * @custom:when The user initiates a withdrawal of their unincluded assets
     * @custom:then The initiateTimestamp of the user deposit is set to the current block timestamp
     */
    function test_initiateWithdrawalAfterCooldown() public {
        rebalancer.initiateWithdrawAssets();
        skip(rebalancer.getTimeLimits().actionCooldown);

        rebalancer.initiateWithdrawAssets();

        UserDeposit memory userDeposit = rebalancer.getUserDepositData(address(this));
        assertEq(userDeposit.initiateTimestamp, block.timestamp, "initiate timestamp");
    }

    /**
     * @custom:scenario The user initiates a withdrawal before the cooldown has elapsed
     * @custom:given The user waited more than the deadline but less than the cooldown
     * @custom:when The user initiates a withdrawal of their unincluded assets
     * @custom:then The call reverts with {RebalancerActionCooldown}
     */
    function test_RevertWhen_initiateWithdrawalTooSoon() public {
        rebalancer.initiateWithdrawAssets();
        skip(rebalancer.getTimeLimits().actionCooldown);

        rebalancer.initiateWithdrawAssets();

        skip(rebalancer.getTimeLimits().validationDeadline);

        vm.expectRevert(RebalancerActionCooldown.selector);
        rebalancer.initiateWithdrawAssets();
    }

    /**
     * @custom:scenario The user initiates a withdrawal but they don't have any funds in the rebalancer
     * @custom:given The user has no active or liquidated position or unincluded assets in the rebalancer
     * @custom:when The user initiates a withdrawal of their unincluded assets
     * @custom:then The call reverts with {RebalancerWithdrawalUnauthorized}
     */
    function test_RevertWhen_initiateWithdrawalNotInRebalancer() public {
        vm.expectRevert(RebalancerWithdrawalUnauthorized.selector);
        vm.prank(USER_1);
        rebalancer.initiateWithdrawAssets();
    }

    /**
     * @custom:scenario The user initiates a withdrawal but they have not validated their deposit
     * @custom:given The user has initiated a deposit but hasn't validated it yet
     * @custom:when The user initiates a withdrawal immediately after the deposit
     * @custom:or The user initiates a withdrawal after the validation delay
     * @custom:or The user initiates a withdrawal after the action cooldown
     * @custom:then The call reverts with {RebalancerWithdrawalUnauthorized}
     */
    function test_RevertWhen_initiateWithdrawalDepositNotValidated() public {
        vm.startPrank(USER_1);
        rebalancer.initiateDepositAssets(INITIAL_DEPOSIT, USER_1);

        vm.expectRevert(RebalancerWithdrawalUnauthorized.selector);
        rebalancer.initiateWithdrawAssets();

        skip(rebalancer.getTimeLimits().validationDelay);

        vm.expectRevert(RebalancerWithdrawalUnauthorized.selector);
        rebalancer.initiateWithdrawAssets();

        skip(rebalancer.getTimeLimits().actionCooldown);

        vm.expectRevert(RebalancerWithdrawalUnauthorized.selector);
        rebalancer.initiateWithdrawAssets();
        vm.stopPrank();
    }

    /**
     * @custom:scenario The user initiates a withdrawal but the assets are already used in a position
     * @custom:given The user's deposit was included in the protocol
     * @custom:when The user initiates a withdrawal
     * @custom:then The call reverts with {RebalancerWithdrawalUnauthorized}
     */
    function test_RevertWhen_initiateWithdrawalIncludedInProtocol() public {
        vm.prank(address(usdnProtocol));
        rebalancer.updatePosition(Types.PositionId(0, 0, 0), 0);

        vm.expectRevert(RebalancerWithdrawalUnauthorized.selector);
        rebalancer.initiateWithdrawAssets();
    }
}

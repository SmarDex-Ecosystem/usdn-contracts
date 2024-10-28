// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { USER_1 } from "../../utils/Constants.sol";
import { RebalancerFixture } from "./utils/Fixtures.sol";

import { IUsdnProtocolTypes as Types } from "../../../src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";

/**
 * @custom:feature The `initiateDepositAssets` function of the rebalancer contract
 * @custom:background Given a rebalancer contract
 */
contract TestRebalancerInitiateDepositAssets is RebalancerFixture {
    uint88 constant INITIAL_DEPOSIT = 2 ether;

    function setUp() public {
        super._setUp();

        wstETH.mintAndApprove(address(this), 10_000 ether, address(rebalancer), type(uint256).max);
        wstETH.mintAndApprove(USER_1, 10_000 ether, address(rebalancer), type(uint256).max);
    }

    /**
     * @custom:scenario Test the setup
     * @custom:when The setup was performed
     * @custom:then The initial deposit amount is greater than the minimum asset deposit
     */
    function test_setUp() public view {
        assertGe(INITIAL_DEPOSIT, rebalancer.getMinAssetDeposit());
    }

    /**
     * @custom:scenario The user deposits assets
     * @custom:given The user does not have an active position in the Rebalancer
     * @custom:when The user deposits assets with his address as the 'to' address
     * @custom:then The payer assets are transferred to the contract
     * @custom:and The state is updated (position timestamp and amount)
     */
    function test_initiateDepositAssets() public {
        _initiateDepositScenario(INITIAL_DEPOSIT, address(this));
    }

    /**
     * @custom:scenario The user deposits assets for someone else
     * @custom:given The 'to' address does not have an active position in the Rebalancer
     * @custom:when The user deposits assets with another address as the 'to' address
     * @custom:then The payer assets are transferred to the contract
     * @custom:and The state is updated (position timestamp and amount)
     */
    function test_initiateDepositAssetsTo() public {
        _initiateDepositScenario(INITIAL_DEPOSIT, USER_1);
    }

    /**
     * @custom:scenario The user deposits assets after their previous position got liquidated
     * @custom:given A user deposited assets and the position gets liquidated
     * @custom:when The user deposit assets again
     * @custom:then The deposit happens as expected
     */
    function test_depositAfterBeingLiquidated() public {
        rebalancer.initiateDepositAssets(INITIAL_DEPOSIT, address(this));
        skip(rebalancer.getTimeLimits().validationDelay);
        rebalancer.validateDepositAssets();

        vm.prank(address(usdnProtocol));
        rebalancer.updatePosition(Types.PositionId(0, 0, 0), 0);

        vm.prank(address(usdnProtocol));
        rebalancer.notifyPositionLiquidated();

        _initiateDepositScenario(INITIAL_DEPOSIT, address(this));
    }

    /**
     * @custom:scenario The 'to' address deposits assets after their previous position got liquidated
     * @custom:given The 'to' address deposited assets and the position got liquidated
     * @custom:when The user deposit assets again with a 'to' address
     * @custom:then The deposit happens as expected
     */
    function test_depositToAfterBeingLiquidated() public {
        vm.startPrank(USER_1);
        rebalancer.initiateDepositAssets(INITIAL_DEPOSIT, USER_1);
        skip(rebalancer.getTimeLimits().validationDelay);
        rebalancer.validateDepositAssets();
        vm.stopPrank();

        vm.prank(address(usdnProtocol));
        rebalancer.updatePosition(Types.PositionId(0, 0, 0), 0);

        vm.prank(address(usdnProtocol));
        rebalancer.notifyPositionLiquidated();

        _initiateDepositScenario(INITIAL_DEPOSIT, USER_1);
    }

    /**
     * @notice Helper function to test the `initiateDeposit` function
     * @param amount The amount of assets to deposit
     * @param to The address to which the deposit will be assigned
     */
    function _initiateDepositScenario(uint88 amount, address to) internal {
        uint256 rebalancerBalanceBefore = wstETH.balanceOf(address(rebalancer));
        uint256 payerBalanceBefore = wstETH.balanceOf(address(this));
        uint256 toBalanceBefore = wstETH.balanceOf(to);
        uint256 pendingBefore = rebalancer.getPendingAssetsAmount();

        vm.expectEmit();
        emit InitiatedAssetsDeposit(address(this), to, amount, block.timestamp);
        rebalancer.initiateDepositAssets(amount, to);

        assertEq(
            wstETH.balanceOf(address(rebalancer)),
            rebalancerBalanceBefore + amount,
            "The rebalancer should have received the assets"
        );
        assertEq(
            wstETH.balanceOf(address(this)),
            payerBalanceBefore - INITIAL_DEPOSIT,
            "The user should have sent the assets"
        );
        if (to != address(this)) {
            assertEq(wstETH.balanceOf(to), toBalanceBefore, "The balance of `to` should have not changed");
        }
        assertEq(rebalancer.getPendingAssetsAmount(), pendingBefore, "Pending assets should not have changed");

        UserDeposit memory userDeposit = rebalancer.getUserDepositData(to);
        assertEq(userDeposit.entryPositionVersion, 0, "The position version should be zero");
        assertEq(userDeposit.amount, amount, "The amount should have been saved");
        assertEq(userDeposit.initiateTimestamp, uint40(block.timestamp), "The timestamp should have been saved");
    }

    /**
     * @custom:scenario The user tries to deposit assets with 'to' as the zero address
     * @custom:given A user with assets
     * @custom:when The user tries to deposit assets with to as the zero address
     * @custom:then The call reverts with a {RebalancerInvalidAddressTo} error
     */
    function test_RevertWhen_depositZeroAddress() public {
        vm.expectRevert(RebalancerInvalidAddressTo.selector);
        rebalancer.initiateDepositAssets(INITIAL_DEPOSIT, address(0));
    }

    /**
     * @custom:scenario The user tries to deposit too little assets
     * @custom:when `initiateDepositAssets` is called with 0 as the amount
     * @custom:or `initiateDepositAssets` is called with `_minAssetDeposit - 1` as the amount
     * @custom:then The call reverts with a {RebalancerInsufficientAmount} error
     */
    function test_RevertWhen_depositInsufficientAmount() public {
        vm.expectRevert(RebalancerInsufficientAmount.selector);
        rebalancer.initiateDepositAssets(0, address(this));

        uint256 minAssetDeposit = rebalancer.getMinAssetDeposit();
        vm.expectRevert(RebalancerInsufficientAmount.selector);
        rebalancer.initiateDepositAssets(uint88(minAssetDeposit) - 1, address(this));
    }

    /**
     * @custom:scenario The user tries to deposit assets when they have a pending deposit
     * @custom:given The user has initiated a deposit
     * @custom:when The user initiates a new deposit immediately after the first one
     * @custom:or The user initiates a new deposit after the validation delay
     * @custom:or The user initiates a new deposit after the action cooldown
     * @custom:then The call reverts with a {RebalancerDepositUnauthorized} error
     */
    function test_RevertWhen_depositWhenPendingDeposit() public {
        rebalancer.initiateDepositAssets(INITIAL_DEPOSIT, address(this));

        vm.expectRevert(RebalancerDepositUnauthorized.selector);
        rebalancer.initiateDepositAssets(INITIAL_DEPOSIT, address(this));

        skip(rebalancer.getTimeLimits().validationDelay);

        vm.expectRevert(RebalancerDepositUnauthorized.selector);
        rebalancer.initiateDepositAssets(INITIAL_DEPOSIT, address(this));

        skip(rebalancer.getTimeLimits().actionCooldown);

        vm.expectRevert(RebalancerDepositUnauthorized.selector);
        rebalancer.initiateDepositAssets(INITIAL_DEPOSIT, address(this));
    }

    /**
     * @custom:scenario The user tries to deposit assets when they have an existing unincluded deposit
     * @custom:given The user has initiated a deposit and validated it
     * @custom:when The user initiates a new deposit
     * @custom:then The call reverts with a {RebalancerDepositUnauthorized} error
     */
    function test_RevertWhen_depositWhenPendingInclusion() public {
        rebalancer.initiateDepositAssets(INITIAL_DEPOSIT, address(this));
        skip(rebalancer.getTimeLimits().validationDelay);
        rebalancer.validateDepositAssets();

        vm.expectRevert(RebalancerDepositUnauthorized.selector);
        rebalancer.initiateDepositAssets(INITIAL_DEPOSIT, address(this));
    }

    /**
     * @custom:scenario The user tries to deposit assets when they are in a position already
     * @custom:given The user has initiated a deposit, validated it, and the rebalancer got triggered
     * @custom:when The user tries to deposit assets
     * @custom:then The call reverts with a {RebalancerDepositUnauthorized} error
     */
    function test_RevertWhen_depositWhenIncludedInPosition() public {
        rebalancer.initiateDepositAssets(INITIAL_DEPOSIT, address(this));
        skip(rebalancer.getTimeLimits().validationDelay);
        rebalancer.validateDepositAssets();

        vm.prank(address(usdnProtocol));
        rebalancer.updatePosition(Types.PositionId(0, 0, 0), 0);

        vm.expectRevert(RebalancerDepositUnauthorized.selector);
        rebalancer.initiateDepositAssets(INITIAL_DEPOSIT, address(this));
    }

    /**
     * @custom:scenario The user tries to deposit assets when they have initiated a withdrawal
     * @custom:given The user has initiated a deposit and validated it, then initiated a withdrawal
     * @custom:when The user tries to deposit assets immediately after the withdrawal
     * @custom:or The user tries to deposit assets after the validation delay
     * @custom:or The user tries to deposit assets after the action cooldown
     * @custom:then The call reverts with a {RebalancerDepositUnauthorized} error
     */
    function test_RevertWhen_depositWhenInitiatedWithdrawal() public {
        rebalancer.initiateDepositAssets(INITIAL_DEPOSIT, address(this));
        skip(rebalancer.getTimeLimits().validationDelay);
        rebalancer.validateDepositAssets();
        rebalancer.initiateWithdrawAssets();

        vm.expectRevert(RebalancerDepositUnauthorized.selector);
        rebalancer.initiateDepositAssets(INITIAL_DEPOSIT, address(this));

        skip(rebalancer.getTimeLimits().validationDelay);

        vm.expectRevert(RebalancerDepositUnauthorized.selector);
        rebalancer.initiateDepositAssets(INITIAL_DEPOSIT, address(this));

        skip(rebalancer.getTimeLimits().actionCooldown);

        vm.expectRevert(RebalancerDepositUnauthorized.selector);
        rebalancer.initiateDepositAssets(INITIAL_DEPOSIT, address(this));
    }
}

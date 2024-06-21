// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import { RebalancerFixture } from "./utils/Fixtures.sol";

/**
 * @custom:feature The `initiateDepositAssets` function of the rebalancer contract
 * @custom:background Given a rebalancer contract
 */
contract TestRebalancerInitiateDepositAssets is RebalancerFixture {
    uint88 constant INITIAL_DEPOSIT = 2 ether;

    function setUp() public {
        super._setUp();

        wstETH.mintAndApprove(address(this), 10_000 ether, address(rebalancer), type(uint256).max);
    }

    /**
     * @custom:scenario Test the setup
     * @custom:when The setup was performed
     * @custom:then The initial deposit amount is greater than the minimum asset deposit
     */
    function test_setUp() public {
        assertGe(INITIAL_DEPOSIT, rebalancer.getMinAssetDeposit());
    }

    /**
     * @custom:scenario The user deposits assets
     * @custom:given The user does not have an active position in the Rebalancer
     * @custom:when The user deposits assets with his address as the 'to' address
     * @custom:then His assets are transferred to the contract
     * @custom:and The state is updated (position timestamp and amount)
     */
    function test_initiateDepositAssets() public {
        uint256 rebalancerBalanceBefore = wstETH.balanceOf(address(rebalancer));
        uint256 userBalanceBefore = wstETH.balanceOf(address(this));
        uint256 pendingBefore = rebalancer.getPendingAssetsAmount();

        vm.expectEmit();
        emit InitiatedAssetsDeposit(address(this), address(this), INITIAL_DEPOSIT, block.timestamp);
        rebalancer.initiateDepositAssets(INITIAL_DEPOSIT, address(this));

        assertEq(
            rebalancerBalanceBefore + INITIAL_DEPOSIT,
            wstETH.balanceOf(address(rebalancer)),
            "The rebalancer should have received the assets"
        );
        assertEq(
            userBalanceBefore - INITIAL_DEPOSIT, wstETH.balanceOf(address(this)), "The user should have sent the assets"
        );
        assertEq(rebalancer.getPendingAssetsAmount(), pendingBefore, "Pending assets should not have changed");

        UserDeposit memory userDeposit = rebalancer.getUserDepositData(address(this));
        assertEq(userDeposit.entryPositionVersion, 0, "The position version should be zero");
        assertEq(userDeposit.amount, INITIAL_DEPOSIT, "The amount should have been saved");
        assertEq(userDeposit.initiateTimestamp, uint40(block.timestamp), "The timestamp should have been saved");
    }

    /**
     * @custom:scenario The user deposit assets after his previous position got liquidated
     * @custom:given A user deposited assets and the position got liquidated
     * @custom:when The user deposit assets again
     * @custom:then His assets are transferred to the contract
     */
    function test_depositAfterBeingLiquidated() public {
        rebalancer.initiateDepositAssets(INITIAL_DEPOSIT, address(this));
        skip(rebalancer.getTimeLimits().validationDelay);
        rebalancer.validateDepositAssets();

        rebalancer.incrementPositionVersion();
        rebalancer.setLastLiquidatedVersion(rebalancer.getPositionVersion());

        uint88 newDepositAmount = 2 * INITIAL_DEPOSIT;

        vm.expectEmit();
        emit InitiatedAssetsDeposit(address(this), address(this), newDepositAmount, block.timestamp);
        rebalancer.initiateDepositAssets(newDepositAmount, address(this));

        UserDeposit memory userDeposit = rebalancer.getUserDepositData(address(this));
        assertEq(userDeposit.entryPositionVersion, 0, "The position version should be the expected one");
        assertEq(userDeposit.amount, newDepositAmount, "The amount should have been saved");
    }

    /**
     * @custom:scenario The user tries to deposit assets with 'to' as the zero address
     * @custom:given A user with assets
     * @custom:when The user tries to deposit assets with to as the zero address
     * @custom:then The call reverts with a RebalancerInvalidAddressTo error
     */
    function test_RevertWhen_depositZeroAddress() public {
        vm.expectRevert(RebalancerInvalidAddressTo.selector);
        rebalancer.initiateDepositAssets(INITIAL_DEPOSIT, address(0));
    }

    /**
     * @custom:scenario The user tries to deposit assets with 0 as the amount
     * @custom:when initiateDepositAssets is called with 0 as the amount
     * @custom:then The call reverts with a RebalancerInsufficientAmount error
     */
    function test_RevertWhen_depositInsufficientAmount() public {
        vm.expectRevert(RebalancerInsufficientAmount.selector);
        rebalancer.initiateDepositAssets(0, address(this));

        uint256 minAssetDeposit = rebalancer.getMinAssetDeposit();
        vm.expectRevert(RebalancerInsufficientAmount.selector);
        rebalancer.initiateDepositAssets(uint88(minAssetDeposit) - 1, address(this));
    }

    /**
     * @custom:scenario The user tries to deposit assets after the position version has changed
     * @custom:given A user that deposited assets in the contract
     * @custom:when The position version is incremented
     * @custom:and The user tries to deposit more assets
     * @custom:then The call reverts with a RebalancerUserInPosition error
     */
    function test_RevertWhen_depositAfterVersionChanged() public {
        rebalancer.initiateDepositAssets(INITIAL_DEPOSIT, address(this));
        skip(rebalancer.getTimeLimits().validationDelay);
        rebalancer.validateDepositAssets();
        rebalancer.incrementPositionVersion();

        vm.expectRevert(RebalancerUserInPosition.selector);
        rebalancer.initiateDepositAssets(INITIAL_DEPOSIT, address(this));
    }

    /**
     * @custom:scenario The user deposits assets again
     * @custom:given A user who deposited already
     * @custom:when The user deposits assets again with his address as the 'to' address
     * @custom:then The contract reverts with `RebalancerUserAlreadyPending`
     */
    function test_RevertWhen_depositTwice() public {
        rebalancer.initiateDepositAssets(INITIAL_DEPOSIT, address(this));
        skip(rebalancer.getTimeLimits().validationDelay);
        rebalancer.validateDepositAssets();

        vm.expectRevert(RebalancerUserAlreadyPending.selector);
        rebalancer.initiateDepositAssets(INITIAL_DEPOSIT, address(this));
    }

    /**
     * @custom:scenario The user deposits again before validating
     * @custom:given A user initiated a deposit
     * @custom:when The user initiates a second deposit with the same address
     * @custom:then The contract reverts with `RebalancerActionNotValidated`
     */
    function test_RevertWhen_depositWithPendingDeposit() public {
        rebalancer.initiateDepositAssets(INITIAL_DEPOSIT, address(this));

        vm.expectRevert(RebalancerActionNotValidated.selector);
        rebalancer.initiateDepositAssets(INITIAL_DEPOSIT, address(this));
    }
}

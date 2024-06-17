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
        assertGe(INITIAL_DEPOSIT, rebalancer.getMinAssetDeposit());
    }

    /**
     * @custom:scenario The user tries to deposit more assets after the position version has changed
     * @custom:given A user that deposited assets in the contract
     * @custom:when The position version is incremented
     * @custom:and The user tries to deposit more assets
     * @custom:then The call reverts with a RebalancerUserNotPending error
     */
    function test_RevertWhen_depositAfterVersionChanged() external {
        rebalancer.initiateDepositAssets(INITIAL_DEPOSIT, address(this));
        skip(rebalancer.getTimeLimits().validationDelay);
        rebalancer.validateDepositAssets();
        rebalancer.incrementPositionVersion();

        vm.expectRevert(RebalancerUserNotPending.selector);
        rebalancer.initiateDepositAssets(INITIAL_DEPOSIT, address(this));
    }

    /**
     * @custom:scenario The user tries to deposit assets with 'to' as the zero address
     * @custom:given A user with assets
     * @custom:when The user tries to deposit assets with to as the zero address
     * @custom:then The call reverts with a RebalancerInvalidAddressTo error
     */
    function test_RevertWhen_depositZeroAddress() external {
        vm.expectRevert(RebalancerInvalidAddressTo.selector);
        rebalancer.initiateDepositAssets(INITIAL_DEPOSIT, address(0));
    }

    /**
     * @custom:scenario The user tries to deposit assets with 0 as the amount
     * @custom:when depositAssets is called with 0 as the amount
     * @custom:then The call reverts with a RebalancerInvalidAmount error
     */
    function test_RevertWhen_depositInsufficientAmount() external {
        vm.expectRevert(RebalancerInsufficientAmount.selector);
        rebalancer.initiateDepositAssets(0, address(this));

        uint256 minAssetDeposit = rebalancer.getMinAssetDeposit();
        vm.expectRevert(RebalancerInsufficientAmount.selector);
        rebalancer.initiateDepositAssets(uint88(minAssetDeposit) - 1, address(this));
    }

    /**
     * @custom:scenario The user deposit assets
     * @custom:given A user with assets
     * @custom:when The user deposits assets with his address as the 'to' address
     * @custom:then His assets are transferred to the contract
     */
    function test_initiateDepositAssets() external {
        uint256 rebalancerBalanceBefore = wstETH.balanceOf(address(rebalancer));
        uint256 userBalanceBefore = wstETH.balanceOf(address(this));

        vm.expectEmit();
        emit InitiatedAssetsDeposit(address(this), INITIAL_DEPOSIT, block.timestamp);
        rebalancer.initiateDepositAssets(INITIAL_DEPOSIT, address(this));

        assertEq(
            rebalancerBalanceBefore + INITIAL_DEPOSIT,
            wstETH.balanceOf(address(rebalancer)),
            "The rebalancer should have received the assets"
        );
        assertEq(
            userBalanceBefore - INITIAL_DEPOSIT, wstETH.balanceOf(address(this)), "The user should have sent the assets"
        );

        UserDeposit memory userDeposit = rebalancer.getUserDepositData(address(this));
        assertEq(userDeposit.entryPositionVersion, 0, "The position version should be zero");
        assertEq(userDeposit.amount, INITIAL_DEPOSIT, "The amount should have been saved");
        assertEq(userDeposit.initiateTimestamp, uint40(block.timestamp), "The timestamp should have been saved");
    }

    /**
     * @custom:scenario The user deposit assets again
     * @custom:given A user with assets already deposited
     * @custom:when The user deposits assets again with his address as the 'to' address
     * @custom:then His assets are transferred to the contract
     * @custom:and the sum of deposits is saved
     */
    function test_RevertWhen_depositAssetsTwice() external {
        rebalancer.initiateDepositAssets(INITIAL_DEPOSIT, address(this));
        skip(rebalancer.getTimeLimits().validationDelay);
        rebalancer.validateDepositAssets();

        vm.expectRevert(RebalancerUserAlreadyPending.selector);
        rebalancer.initiateDepositAssets(INITIAL_DEPOSIT, address(this));
    }

    /**
     * @custom:scenario The user deposit assets after his previous assets got liquidated
     * @custom:given A user with deposited assets
     * @custom:and The position the assets were in got liquidated
     * @custom:when The user deposit assets again
     * @custom:then His assets are transferred to the contract
     */
    function test_depositAfterBeingLiquidated() external {
        rebalancer.initiateDepositAssets(INITIAL_DEPOSIT, address(this));
        skip(rebalancer.getTimeLimits().validationDelay);
        rebalancer.validateDepositAssets();

        rebalancer.incrementPositionVersion();
        rebalancer.setLastLiquidatedVersion(rebalancer.getPositionVersion());

        uint88 newDepositAmount = 2 * INITIAL_DEPOSIT;

        vm.expectEmit();
        emit InitiatedAssetsDeposit(address(this), newDepositAmount, block.timestamp);
        rebalancer.initiateDepositAssets(newDepositAmount, address(this));

        UserDeposit memory userDeposit = rebalancer.getUserDepositData(address(this));
        assertEq(userDeposit.entryPositionVersion, 0, "The position version should be the expected one");
        assertEq(userDeposit.amount, newDepositAmount, "The amount should have been saved");
    }
}

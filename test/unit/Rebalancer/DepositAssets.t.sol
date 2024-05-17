// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { RebalancerFixture } from "test/unit/Rebalancer/utils/Fixtures.sol";

/**
 * @custom:feature The depositAssets function of the rebalancer contract
 * @custom:background Given an rebalancer contract
 */
contract TestRebalancerDepositAssets is RebalancerFixture {
    function setUp() public {
        super._setUp();

        wstETH.mintAndApprove(address(this), 10_000 ether, address(rebalancer), type(uint256).max);
    }

    /**
     * @custom:scenario The user tries to deposit more assets after the position version has changed
     * @custom:given A user that deposited assets in the contract
     * @custom:when The position version is incremented
     * @custom:and The user tries to deposit more assets
     * @custom:then The call reverts with a RebalancerUserNotPending error
     */
    function test_RevertWhen_depositAssetsAfterVersionChanged() external {
        rebalancer.depositAssets(1 ether, address(this));
        rebalancer.incrementPositionVersion();

        vm.expectRevert(RebalancerUserNotPending.selector);
        rebalancer.depositAssets(1 ether, address(this));
    }

    /**
     * @custom:scenario The user tries to deposit assets with to as the zero address
     * @custom:given A user with assets
     * @custom:when The user tries to deposit assets with to as the zero address
     * @custom:then The call reverts with a RebalancerInvalidAddressTo error
     */
    function test_RevertWhen_depositAssetsToTheZeroAddress() external {
        vm.expectRevert(RebalancerInvalidAddressTo.selector);
        rebalancer.depositAssets(1 ether, address(0));
    }

    /**
     * @custom:scenario The user tries to deposit assets with 0 as the amount
     * @custom:when depositAssets is called with 0 as the amount
     * @custom:then The call reverts with a RebalancerInvalidAmount error
     */
    function test_RevertWhen_depositAssetsWithAmountZero() external {
        vm.expectRevert(RebalancerInvalidAmount.selector);
        rebalancer.depositAssets(0, address(this));
    }

    /**
     * @custom:scenario The user deposit assets
     * @custom:given A user with assets
     * @custom:when The user deposit assets with his address as the to address
     * @custom:then His assets are transferred to the contract
     */
    function test_depositAssets() external {
        uint128 expectedPositionVersion = rebalancer.getPositionVersion() + 1;
        uint256 rebalancerBalanceBefore = wstETH.balanceOf(address(rebalancer));
        uint256 userBalanceBefore = wstETH.balanceOf(address(this));

        vm.expectEmit();
        emit AssetsDeposited(1 ether, address(this), expectedPositionVersion);
        rebalancer.depositAssets(1 ether, address(this));

        assertEq(
            rebalancerBalanceBefore + 1 ether,
            wstETH.balanceOf(address(rebalancer)),
            "The rebalancer should have received the assets"
        );
        assertEq(userBalanceBefore - 1 ether, wstETH.balanceOf(address(this)), "The user should have sent the assets");

        UserDeposit memory userDeposit = rebalancer.getUserDepositData(address(this));
        assertEq(
            userDeposit.entryPositionVersion, expectedPositionVersion, "The position version should be the expected one"
        );
        assertEq(userDeposit.amount, 1 ether, "The amount should have been saved");
    }

    /**
     * @custom:scenario The user deposit assets again
     * @custom:given A user with assets already deposited
     * @custom:when The user deposit assets again with his address as the to address
     * @custom:then His assets are transferred to the contract
     * @custom:and the sum of deposits is saved
     */
    function test_depositAssetsTwice() external {
        uint128 expectedPositionVersion = rebalancer.getPositionVersion() + 1;
        uint128 firstDepositAmount = 1 ether;
        rebalancer.depositAssets(firstDepositAmount, address(this));

        uint128 secondDepositAmount = 0.5 ether;
        uint256 rebalancerBalanceBefore = wstETH.balanceOf(address(rebalancer));
        uint256 userBalanceBefore = wstETH.balanceOf(address(this));
        vm.expectEmit();
        emit AssetsDeposited(secondDepositAmount, address(this), expectedPositionVersion);
        rebalancer.depositAssets(secondDepositAmount, address(this));

        assertEq(
            rebalancerBalanceBefore + secondDepositAmount,
            wstETH.balanceOf(address(rebalancer)),
            "The rebalancer should have received the assets"
        );
        assertEq(
            userBalanceBefore - secondDepositAmount,
            wstETH.balanceOf(address(this)),
            "The user should have sent the assets"
        );

        UserDeposit memory userDeposit = rebalancer.getUserDepositData(address(this));
        assertEq(
            userDeposit.entryPositionVersion, expectedPositionVersion, "The position version should be the expected one"
        );
        assertEq(
            userDeposit.amount, firstDepositAmount + secondDepositAmount, "The sum of amounts should have been saved"
        );
    }

    /**
     * @custom:scenario The user deposit assets after his previous assets got liquidated
     * @custom:given A user with deposited assets
     * @custom:and the position the assets were in got liquidated
     * @custom:when The user deposit assets again
     * @custom:then His assets are transferred to the contract
     */
    function test_depositAssetsAfterBeingLiquidated() external {
        rebalancer.depositAssets(1 ether, address(this));
        rebalancer.incrementPositionVersion();
        rebalancer.setLastLiquidatedVersion(rebalancer.getPositionVersion());

        uint128 expectedPositionVersion = rebalancer.getPositionVersion() + 1;

        uint128 newDepositAmount = 0.5 ether;
        vm.expectEmit();
        emit AssetsDeposited(newDepositAmount, address(this), expectedPositionVersion);
        rebalancer.depositAssets(newDepositAmount, address(this));

        UserDeposit memory userDeposit = rebalancer.getUserDepositData(address(this));
        assertEq(
            userDeposit.entryPositionVersion, expectedPositionVersion, "The position version should be the expected one"
        );
        assertEq(userDeposit.amount, newDepositAmount, "The amount should have been saved");
    }
}

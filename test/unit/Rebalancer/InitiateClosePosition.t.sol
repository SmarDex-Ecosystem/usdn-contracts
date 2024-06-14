// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import { IRebalancerErrors } from "../../../src/interfaces/Rebalancer/IRebalancerErrors.sol";

import { RebalancerFixture } from "../../../test/unit/Rebalancer/utils/Fixtures.sol";

/**
 * @custom:feature The `initiateClosePosition` function of the rebalancer contract
 * @custom:background Given a rebalancer contract
 */
contract TestRebalancerInitiateClosePosition is RebalancerFixture {
    uint128 internal minAsset;

    function setUp() public {
        super._setUp();

        wstETH.mintAndApprove(address(this), 1000 ether, address(rebalancer), type(uint256).max);
        minAsset = uint128(rebalancer.getMinAssetDeposit());
        rebalancer.depositAssets(minAsset, address(this));
    }

    /**
     * @custom:scenario Call the rebalancer `initiateClosePosition` function with invalid `to`
     * @custom:given A rebalancer contract
     * @custom:when The `initiateClosePosition` function is called
     * @custom:then It should revert with `RebalancerInvalidAddressTo`
     */
    function test_RevertWhenRebalancerInvalidTo() external {
        vm.expectRevert(IRebalancerErrors.RebalancerInvalidAddressTo.selector);
        rebalancer.initiateClosePosition(minAsset, address(0), payable(address(this)), "", EMPTY_PREVIOUS_DATA);
    }

    /**
     * @custom:scenario Call the rebalancer `initiateClosePosition` function with invalid `validator`
     * @custom:given A rebalancer contract
     * @custom:when The `initiateClosePosition` function is called
     * @custom:then It should revert with `RebalancerInvalidAddressValidator`
     */
    function test_RevertWhenRebalancerInvalidValidator() external {
        vm.expectRevert(IRebalancerErrors.RebalancerInvalidAddressValidator.selector);
        rebalancer.initiateClosePosition(minAsset, address(this), payable(address(0)), "", EMPTY_PREVIOUS_DATA);
    }

    /**
     * @custom:scenario Call the rebalancer `initiateClosePosition` function without user pending deposit
     * @custom:given A rebalancer contract
     * @custom:when The `initiateClosePosition` function is called
     * @custom:then It should revert with `RebalancerUserNotPending`
     */
    function test_RevertWhenRebalancerUserNotPending() external {
        rebalancer.withdrawPendingAssets(uint128(minAsset), address(this));
        vm.expectRevert(IRebalancerErrors.RebalancerUserNotPending.selector);
        rebalancer.initiateClosePosition(minAsset, address(this), payable(address(this)), "", EMPTY_PREVIOUS_DATA);
    }

    /**
     * @custom:scenario Call the rebalancer `initiateClosePosition` function without rebalanced assets
     * @custom:given A rebalancer contract
     * @custom:when The `initiateClosePosition` function is called
     * @custom:then It should revert with `RebalancerNoRebalancedAssets`
     */
    function test_RevertWhenRebalancerNoRebalancedAssets() external {
        vm.expectRevert(IRebalancerErrors.RebalancerNoRebalancedAssets.selector);
        rebalancer.initiateClosePosition(minAsset, address(this), payable(address(this)), "", EMPTY_PREVIOUS_DATA);
    }
}

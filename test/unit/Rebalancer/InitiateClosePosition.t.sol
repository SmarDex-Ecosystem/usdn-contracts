// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { RebalancerFixture } from "../../../test/unit/Rebalancer/utils/Fixtures.sol";
import { USER_1 } from "../../utils/Constants.sol";

import { IRebalancerErrors } from "../../../src/interfaces/Rebalancer/IRebalancerErrors.sol";

/**
 * @custom:feature The `initiateClosePosition` function of the rebalancer contract
 * @custom:background Given a rebalancer contract with an initial user deposit
 */
contract TestRebalancerInitiateClosePosition is RebalancerFixture {
    uint88 internal minAsset;

    function setUp() public {
        super._setUp();

        wstETH.mintAndApprove(address(this), 1000 ether, address(rebalancer), type(uint256).max);
        wstETH.mintAndApprove(USER_1, 1000 ether, address(rebalancer), type(uint256).max);
        minAsset = uint88(rebalancer.getMinAssetDeposit());
        rebalancer.initiateDepositAssets(minAsset, address(this));
        skip(rebalancer.getTimeLimits().validationDelay);
        rebalancer.validateDepositAssets();
        vm.warp(rebalancer.getCloseLockedUntil() + 1);
    }

    /**
     * @custom:scenario Call `initiateClosePosition` function with zero amount
     * @custom:when The `initiateClosePosition` function is called with zero amount
     * @custom:then It should revert with `RebalancerInvalidAmount`
     */
    function test_RevertWhen_rebalancerInvalidAmountZero() public {
        vm.expectRevert(IRebalancerErrors.RebalancerInvalidAmount.selector);
        rebalancer.initiateClosePosition(
            0, address(this), payable(this), DISABLE_MIN_PRICE, type(uint256).max, "", EMPTY_PREVIOUS_DATA, ""
        );
    }

    /**
     * @custom:scenario Call `initiateClosePosition` function with a too large amount
     * @custom:when The `initiateClosePosition` function is called with more than the user rebalancer amount
     * @custom:then It should revert with `RebalancerInvalidAmount`
     */
    function test_RevertWhen_rebalancerInvalidAmountTooLarge() public {
        vm.expectRevert(IRebalancerErrors.RebalancerInvalidAmount.selector);
        rebalancer.initiateClosePosition(
            minAsset + 1,
            address(this),
            payable(this),
            DISABLE_MIN_PRICE,
            type(uint256).max,
            "",
            EMPTY_PREVIOUS_DATA,
            ""
        );
    }

    /**
     * @custom:scenario Call `initiateClosePosition` function with a too low remaining amount
     * @custom:when The `initiateClosePosition` function is called with a remaining amount
     * lower than the rebalancer minimum amount
     * @custom:then It should revert with `RebalancerInvalidAmount`
     */
    function test_RevertWhen_rebalancerInvalidAmountTooLow() public {
        vm.expectRevert(IRebalancerErrors.RebalancerInvalidAmount.selector);
        rebalancer.initiateClosePosition(
            1, address(this), payable(this), DISABLE_MIN_PRICE, type(uint256).max, "", EMPTY_PREVIOUS_DATA, ""
        );
    }

    /**
     * @custom:scenario Call `initiateClosePosition` function with pending assets
     * @custom:when The `initiateClosePosition` function is called with pending assets
     * @custom:then It should revert with `RebalancerUserPending`
     */
    function test_RevertWhen_rebalancerUserPending() public {
        vm.expectRevert(IRebalancerErrors.RebalancerUserPending.selector);
        rebalancer.initiateClosePosition(
            minAsset, address(this), payable(this), DISABLE_MIN_PRICE, type(uint256).max, "", EMPTY_PREVIOUS_DATA, ""
        );
    }

    /**
     * @custom:scenario Call `initiateClosePosition` function without having validated the deposit
     * @custom:when The `initiateClosePosition` function is called by a user that did not validate it deposit
     * @custom:then It should revert with `RebalancerUserPending`
     */
    function test_RevertWhen_rebalancerUserNotInRebalancer() public {
        vm.startPrank(USER_1);
        rebalancer.initiateDepositAssets(minAsset, USER_1);
        vm.expectRevert(IRebalancerErrors.RebalancerUserPending.selector);
        rebalancer.initiateClosePosition(
            minAsset, USER_1, USER_1, DISABLE_MIN_PRICE, type(uint256).max, "", EMPTY_PREVIOUS_DATA, ""
        );
        vm.stopPrank();
    }

    /**
     * @custom:scenario Call {initiateClosePosition} function with a timestamp before the {closeLockedUntil}
     * @custom:when The {initiateClosePosition} function is called
     * @custom:then It should revert with {RebalancerCloseLockedUntil}
     */
    function test_RevertWhen_rebalancerBeforeCloseLockedUntil() public {
        vm.warp(block.timestamp - 1);

        vm.expectRevert(
            abi.encodeWithSelector(
                IRebalancerErrors.RebalancerCloseLockedUntil.selector, rebalancer.getCloseLockedUntil()
            )
        );
        rebalancer.initiateClosePosition(
            minAsset, address(this), payable(this), DISABLE_MIN_PRICE, type(uint256).max, "", EMPTY_PREVIOUS_DATA, ""
        );
    }

    receive() external payable { }
}

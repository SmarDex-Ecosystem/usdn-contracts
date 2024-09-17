// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

import { USER_1 } from "../../utils/Constants.sol";
import { LiquidationRewardsManagerBaseFixture } from "./utils/Fixtures.sol";

import { ILiquidationRewardsManagerErrorsEventsTypes } from
    "../../../src/interfaces/LiquidationRewardsManager/ILiquidationRewardsManagerErrorsEventsTypes.sol";

/**
 * @custom:feature The `setRewardsParameters` function of `LiquidationRewardsManager`
 */
contract TestLiquidationRewardsManagerSetRewardsParameters is
    LiquidationRewardsManagerBaseFixture,
    ILiquidationRewardsManagerErrorsEventsTypes
{
    uint32 gasUsedPerTick;
    uint32 otherGasUsed;
    uint32 rebaseGasUsed;
    uint32 rebalancerGasUsed;
    uint64 baseFeeOffset;
    uint16 gasMultiplierBps;
    uint16 positionBonusMultiplierBps;
    uint128 fixedReward;
    uint128 maxReward;

    function setUp() public override {
        super.setUp();

        gasUsedPerTick = 500_000;
        otherGasUsed = 1_000_000;
        rebaseGasUsed = 200_000;
        rebalancerGasUsed = 300_000;
        baseFeeOffset = 10 gwei;
        gasMultiplierBps = type(uint16).max;
        positionBonusMultiplierBps = 1;
        fixedReward = 0.05 ether;
        maxReward = 0.1 ether;
    }

    /**
     * @custom:scenario Call `setRewardsParameters` with valid values
     * @custom:when The values are within the limits
     * @custom:then It should succeed
     * @custom:and The `getRewardsParameters` should return the newly set values
     * @custom:and The `RewardsParametersUpdated` event should be emitted
     */
    function test_setRewardsParametersWithValidValues() public {
        vm.expectEmit();
        emit RewardsParametersUpdated(
            gasUsedPerTick,
            otherGasUsed,
            rebaseGasUsed,
            rebalancerGasUsed,
            baseFeeOffset,
            gasMultiplierBps,
            positionBonusMultiplierBps,
            fixedReward,
            maxReward
        );
        liquidationRewardsManager.setRewardsParameters(
            gasUsedPerTick,
            otherGasUsed,
            rebaseGasUsed,
            rebalancerGasUsed,
            baseFeeOffset,
            gasMultiplierBps,
            positionBonusMultiplierBps,
            fixedReward,
            maxReward
        );

        RewardsParameters memory rewardsParameters = liquidationRewardsManager.getRewardsParameters();

        assertEq(gasUsedPerTick, rewardsParameters.gasUsedPerTick, "The gasUsedPerTick variable was not updated");
        assertEq(otherGasUsed, rewardsParameters.otherGasUsed, "The otherGasUsed variable was not updated");
        assertEq(rebaseGasUsed, rewardsParameters.rebaseGasUsed, "The rebaseGasUsed variable was not updated");
        assertEq(
            rebalancerGasUsed, rewardsParameters.rebalancerGasUsed, "The rebalancerGasUsed variable was not updated"
        );
        assertEq(baseFeeOffset, rewardsParameters.baseFeeOffset, "The baseFeeOffset variable was not updated");
        assertEq(gasMultiplierBps, rewardsParameters.gasMultiplierBps, "The gasMultiplierBps variable was not updated");
        assertEq(
            positionBonusMultiplierBps,
            rewardsParameters.positionBonusMultiplierBps,
            "The positionBonusMultiplierBps variable was not updated"
        );
        assertEq(fixedReward, rewardsParameters.fixedReward, "The fixedReward variable was not updated");
        assertEq(maxReward, rewardsParameters.maxReward, "The maxReward variable was not updated");
    }

    /**
     * @custom:scenario Call `setRewardsParameters` reverts when caller is not the owner
     * @custom:when The caller is not the owner
     * @custom:then It reverts with a OwnableUnauthorizedAccount error
     */
    function test_RevertWhen_setRewardsParametersCallerIsNotTheOwner() public {
        vm.prank(USER_1);

        // Revert as USER_1 is not the owner
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, USER_1));
        liquidationRewardsManager.setRewardsParameters(
            gasUsedPerTick,
            otherGasUsed,
            rebaseGasUsed,
            rebalancerGasUsed,
            baseFeeOffset,
            gasMultiplierBps,
            positionBonusMultiplierBps,
            fixedReward,
            maxReward
        );
    }

    /**
     * @custom:scenario Call `setRewardsParameters` reverts when the gasUsedPerTick is too high
     * @custom:when The value of gasUsedPerTick is bigger than the limit
     * @custom:and The other parameters are within the limits
     * @custom:then It reverts with a LiquidationRewardsManagerGasUsedPerTickTooHigh error
     */
    function test_RevertWhen_setRewardsParametersWithGasUsedPerTickTooHigh() public {
        gasUsedPerTick = 500_001;

        // Expect revert when the gas used per tick parameter is too high
        vm.expectRevert(abi.encodeWithSelector(LiquidationRewardsManagerGasUsedPerTickTooHigh.selector, gasUsedPerTick));
        liquidationRewardsManager.setRewardsParameters(
            gasUsedPerTick,
            otherGasUsed,
            rebaseGasUsed,
            rebalancerGasUsed,
            baseFeeOffset,
            gasMultiplierBps,
            positionBonusMultiplierBps,
            fixedReward,
            maxReward
        );
    }

    /**
     * @custom:scenario Call `setRewardsParameters` reverts when the otherGasUsed is too high
     * @custom:when The value of otherGasUsed is bigger than the limit
     * @custom:and The other parameters are within the limits
     * @custom:then It reverts with a LiquidationRewardsManagerOtherGasUsedTooHigh error
     */
    function test_RevertWhen_setRewardsParametersWithOtherGasUsedTooHigh() public {
        otherGasUsed = 1_000_001;

        // Expect revert when the other gas used parameter is too high
        vm.expectRevert(abi.encodeWithSelector(LiquidationRewardsManagerOtherGasUsedTooHigh.selector, otherGasUsed));
        liquidationRewardsManager.setRewardsParameters(
            gasUsedPerTick,
            otherGasUsed,
            rebaseGasUsed,
            rebalancerGasUsed,
            baseFeeOffset,
            gasMultiplierBps,
            positionBonusMultiplierBps,
            fixedReward,
            maxReward
        );
    }

    /**
     * @custom:scenario Call `setRewardsParameters` reverts when the rebaseGasUsed is too high
     * @custom:when The value of rebaseGasUsed is bigger than the limit
     * @custom:and The other parameters are within the limits
     * @custom:then It reverts with a LiquidationRewardsManagerRebaseGasUsedTooHigh error
     */
    function test_RevertWhen_setRewardsParametersWithRebaseGasUsedTooHigh() public {
        rebaseGasUsed = 200_001;

        // Expect revert when the other gas used parameter is too high
        vm.expectRevert(abi.encodeWithSelector(LiquidationRewardsManagerRebaseGasUsedTooHigh.selector, rebaseGasUsed));
        liquidationRewardsManager.setRewardsParameters(
            gasUsedPerTick,
            otherGasUsed,
            rebaseGasUsed,
            rebalancerGasUsed,
            baseFeeOffset,
            gasMultiplierBps,
            positionBonusMultiplierBps,
            fixedReward,
            maxReward
        );
    }

    /**
     * @custom:scenario Call `setRewardsParameters` reverts when the rebalancerGasUsed is too high
     * @custom:when The value of rebalancerGasUsed is bigger than the limit
     * @custom:and The other parameters are within the limits
     * @custom:then It reverts with a LiquidationRewardsManagerRebalancerGasUsedTooHigh error
     */
    function test_RevertWhen_setRewardsParametersWithRebalancerGasUsedTooHigh() public {
        rebalancerGasUsed = 300_001;

        // Expect revert when the other gas used parameter is too high
        vm.expectRevert(
            abi.encodeWithSelector(LiquidationRewardsManagerRebalancerGasUsedTooHigh.selector, rebalancerGasUsed)
        );
        liquidationRewardsManager.setRewardsParameters(
            gasUsedPerTick,
            otherGasUsed,
            rebaseGasUsed,
            rebalancerGasUsed,
            baseFeeOffset,
            gasMultiplierBps,
            positionBonusMultiplierBps,
            fixedReward,
            maxReward
        );
    }

    /**
     * @custom:scenario Call `setRewardsParameters` reverts when the maxReward is too low
     * @custom:when The value of maxReward is smaller than the limit
     * @custom:and The other parameters are within the limits
     * @custom:then It reverts with a LiquidationRewardsManagerMaxRewardTooLow error
     */
    function test_RevertWhen_setRewardsParametersWithMaxRewardTooLow() public {
        maxReward = 0.09 ether;

        // Expect revert when the value of maxReward is too low
        vm.expectRevert(abi.encodeWithSelector(LiquidationRewardsManagerMaxRewardTooLow.selector, maxReward));
        liquidationRewardsManager.setRewardsParameters(
            gasUsedPerTick,
            otherGasUsed,
            rebaseGasUsed,
            rebalancerGasUsed,
            baseFeeOffset,
            gasMultiplierBps,
            positionBonusMultiplierBps,
            fixedReward,
            maxReward
        );
    }
}

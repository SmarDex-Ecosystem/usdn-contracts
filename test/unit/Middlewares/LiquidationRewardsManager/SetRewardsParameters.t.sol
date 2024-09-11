// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

import { USER_1 } from "../../../utils/Constants.sol";
import { LiquidationRewardsManagerBaseFixture } from "../utils/Fixtures.sol";

import { ILiquidationRewardsManagerErrorsEventsTypes } from
    "../../../../src/interfaces/LiquidationRewardsManager/ILiquidationRewardsManagerErrorsEventsTypes.sol";

/**
 * @custom:feature The `setRewardsParameters` function of `LiquidationRewardsManager`
 */
contract TestLiquidationRewardsManagerSetRewardsParameters is
    LiquidationRewardsManagerBaseFixture,
    ILiquidationRewardsManagerErrorsEventsTypes
{
    function setUp() public override {
        super.setUp();
    }

    /**
     * @custom:scenario Call `setRewardsParameters` with valid values
     * @custom:when The values are within the limits
     * @custom:then It should succeed
     * @custom:and The `getRewardsParameters` should return the newly set values
     * @custom:and The `RewardsParametersUpdated` event should be emitted
     */
    function test_setRewardsParametersWithValidValues() public {
        uint32 gasUsedPerTick = 500_000;
        uint32 otherGasUsed = 1_000_000;
        uint32 rebaseGasUsed = 200_000;
        uint32 rebalancerGasUsed = 300_000;
        uint64 gasPriceLimit = 8000 gwei;
        uint32 multiplierBps = 10 * liquidationRewardsManager.BPS_DIVISOR();

        vm.expectEmit();
        emit RewardsParametersUpdated(
            gasUsedPerTick, otherGasUsed, rebaseGasUsed, rebalancerGasUsed, gasPriceLimit, multiplierBps
        );
        liquidationRewardsManager.setRewardsParameters(
            gasUsedPerTick, otherGasUsed, rebaseGasUsed, rebalancerGasUsed, gasPriceLimit, multiplierBps
        );

        RewardsParameters memory rewardsParameters = liquidationRewardsManager.getRewardsParameters();

        assertEq(gasUsedPerTick, rewardsParameters.gasUsedPerTick, "The gasUsedPerTick variable was not updated");
        assertEq(otherGasUsed, rewardsParameters.otherGasUsed, "The otherGasUsed variable was not updated");
        assertEq(rebaseGasUsed, rewardsParameters.rebaseGasUsed, "The rebaseGasUsed variable was not updated");
        assertEq(gasPriceLimit, rewardsParameters.gasPriceLimit, "The gasPriceLimit variable was not updated");
        assertEq(multiplierBps, rewardsParameters.multiplierBps, "The multiplierBps variable was not updated");
    }

    /**
     * @custom:scenario Call `setRewardsParameters` reverts when caller is not the owner
     * @custom:when The caller is not the owner
     * @custom:then It reverts with a OwnableUnauthorizedAccount error
     */
    function test_RevertWhen_setRewardsParametersCallerIsNotTheOwner() public {
        uint32 gasUsedPerTick = 500_000;
        uint32 otherGasUsed = 1_000_000;
        uint32 rebaseGasUsed = 200_000;
        uint32 rebalancerGasUsed = 300_000;
        uint64 gasPriceLimit = 8000 gwei;
        uint32 multiplierBps = 10 * liquidationRewardsManager.BPS_DIVISOR();

        vm.prank(USER_1);

        // Revert as USER_1 is not the owner
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, USER_1));
        liquidationRewardsManager.setRewardsParameters(
            gasUsedPerTick, otherGasUsed, rebaseGasUsed, rebalancerGasUsed, gasPriceLimit, multiplierBps
        );
    }

    /**
     * @custom:scenario Call `setRewardsParameters` reverts when the gasUsedPerTick is too high
     * @custom:when The value of gasUsedPerTick is bigger than the limit
     * @custom:and The other parameters are within the limits
     * @custom:then It reverts with a LiquidationRewardsManagerGasUsedPerTickTooHigh error
     */
    function test_RevertWhen_setRewardsParametersWithGasUsedPerTickTooHigh() public {
        uint32 gasUsedPerTick = 500_001;
        uint32 otherGasUsed = 1_000_000;
        uint32 rebaseGasUsed = 200_000;
        uint32 rebalancerGasUsed = 300_000;
        uint64 gasPriceLimit = 8000 gwei;
        uint32 multiplierBps = 10 * liquidationRewardsManager.BPS_DIVISOR();

        // Expect revert when the gas used per tick parameter is too high
        vm.expectRevert(abi.encodeWithSelector(LiquidationRewardsManagerGasUsedPerTickTooHigh.selector, gasUsedPerTick));
        liquidationRewardsManager.setRewardsParameters(
            gasUsedPerTick, otherGasUsed, rebaseGasUsed, rebalancerGasUsed, gasPriceLimit, multiplierBps
        );
    }

    /**
     * @custom:scenario Call `setRewardsParameters` reverts when the otherGasUsed is too high
     * @custom:when The value of otherGasUsed is bigger than the limit
     * @custom:and The other parameters are within the limits
     * @custom:then It reverts with a LiquidationRewardsManagerOtherGasUsedTooHigh error
     */
    function test_RevertWhen_setRewardsParametersWithOtherGasUsedTooHigh() public {
        uint32 gasUsedPerTick = 500_000;
        uint32 otherGasUsed = 1_000_001;
        uint32 rebaseGasUsed = 200_000;
        uint32 rebalancerGasUsed = 300_000;
        uint64 gasPriceLimit = 8000 gwei;
        uint32 multiplierBps = 10 * liquidationRewardsManager.BPS_DIVISOR();

        // Expect revert when the other gas used parameter is too high
        vm.expectRevert(abi.encodeWithSelector(LiquidationRewardsManagerOtherGasUsedTooHigh.selector, otherGasUsed));
        liquidationRewardsManager.setRewardsParameters(
            gasUsedPerTick, otherGasUsed, rebaseGasUsed, rebalancerGasUsed, gasPriceLimit, multiplierBps
        );
    }

    /**
     * @custom:scenario Call `setRewardsParameters` reverts when the rebaseGasUsed is too high
     * @custom:when The value of rebaseGasUsed is bigger than the limit
     * @custom:and The other parameters are within the limits
     * @custom:then It reverts with a LiquidationRewardsManagerRebaseGasUsedTooHigh error
     */
    function test_RevertWhen_setRewardsParametersWithRebaseGasUsedTooHigh() public {
        uint32 gasUsedPerTick = 500_000;
        uint32 otherGasUsed = 1_000_000;
        uint32 rebaseGasUsed = 200_001;
        uint32 rebalancerGasUsed = 300_000;
        uint64 gasPriceLimit = 8000 gwei;
        uint32 multiplierBps = 10 * liquidationRewardsManager.BPS_DIVISOR();

        // Expect revert when the other gas used parameter is too high
        vm.expectRevert(abi.encodeWithSelector(LiquidationRewardsManagerRebaseGasUsedTooHigh.selector, rebaseGasUsed));
        liquidationRewardsManager.setRewardsParameters(
            gasUsedPerTick, otherGasUsed, rebaseGasUsed, rebalancerGasUsed, gasPriceLimit, multiplierBps
        );
    }

    /**
     * @custom:scenario Call `setRewardsParameters` reverts when the rebalancerGasUsed is too high
     * @custom:when The value of rebalancerGasUsed is bigger than the limit
     * @custom:and The other parameters are within the limits
     * @custom:then It reverts with a LiquidationRewardsManagerRebalancerGasUsedTooHigh error
     */
    function test_RevertWhen_setRewardsParametersWithRebalancerGasUsedTooHigh() public {
        uint32 gasUsedPerTick = 500_000;
        uint32 otherGasUsed = 1_000_000;
        uint32 rebaseGasUsed = 200_000;
        uint32 rebalancerGasUsed = 300_001;
        uint64 gasPriceLimit = 8000 gwei;
        uint32 multiplierBps = 10 * liquidationRewardsManager.BPS_DIVISOR();

        // Expect revert when the other gas used parameter is too high
        vm.expectRevert(
            abi.encodeWithSelector(LiquidationRewardsManagerRebalancerGasUsedTooHigh.selector, rebalancerGasUsed)
        );
        liquidationRewardsManager.setRewardsParameters(
            gasUsedPerTick, otherGasUsed, rebaseGasUsed, rebalancerGasUsed, gasPriceLimit, multiplierBps
        );
    }

    /**
     * @custom:scenario Call `setRewardsParameters` reverts when the gasPriceLimit is too high
     * @custom:when The value of gasPriceLimit is bigger than the limit
     * @custom:and The other parameters are within the limits
     * @custom:then It reverts with a LiquidationRewardsManagerGasPriceLimitTooHigh error
     */
    function test_RevertWhen_setRewardsParametersWithGasPriceLimitTooHigh() public {
        uint32 gasUsedPerTick = 500_000;
        uint32 otherGasUsed = 1_000_000;
        uint32 rebaseGasUsed = 200_000;
        uint32 rebalancerGasUsed = 300_000;
        uint64 gasPriceLimit = 8000 gwei + 1;
        uint32 multiplierBps = 10 * liquidationRewardsManager.BPS_DIVISOR();

        // Expect revert when the gas price limit parameter is too high
        vm.expectRevert(abi.encodeWithSelector(LiquidationRewardsManagerGasPriceLimitTooHigh.selector, gasPriceLimit));
        liquidationRewardsManager.setRewardsParameters(
            gasUsedPerTick, otherGasUsed, rebaseGasUsed, rebalancerGasUsed, gasPriceLimit, multiplierBps
        );
    }

    /**
     * @custom:scenario Call `setRewardsParameters` reverts when the multiplierBps is too high
     * @custom:when The value of multiplierBps is bigger than the limit
     * @custom:and The other parameters are within the limits
     * @custom:then It reverts with a LiquidationRewardsManagerMultiplierBpsTooHigh error
     */
    function test_RevertWhen_setRewardsParametersWithMultiplierTooHigh() public {
        uint32 gasUsedPerTick = 500_000;
        uint32 otherGasUsed = 1_000_000;
        uint32 rebaseGasUsed = 200_000;
        uint32 rebalancerGasUsed = 300_000;
        uint64 gasPriceLimit = 8000 gwei;
        uint32 multiplierBps = 10 * liquidationRewardsManager.BPS_DIVISOR() + 1;

        // Expect revert when the value of multiplierBps is too high
        vm.expectRevert(abi.encodeWithSelector(LiquidationRewardsManagerMultiplierBpsTooHigh.selector, multiplierBps));
        liquidationRewardsManager.setRewardsParameters(
            gasUsedPerTick, otherGasUsed, rebaseGasUsed, rebalancerGasUsed, gasPriceLimit, multiplierBps
        );
    }
}

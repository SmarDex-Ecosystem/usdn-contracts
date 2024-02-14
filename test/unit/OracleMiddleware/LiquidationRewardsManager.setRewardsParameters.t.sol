// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

import { USER_1 } from "test/utils/Constants.sol";
import { LiquidationRewardsManagerBaseFixture } from "test/unit/OracleMiddleware/utils/Fixtures.sol";
import { LiquidationRewardsManager } from "src/OracleMiddleware/LiquidationRewardsManager.sol";
import { ILiquidationRewardsManagerErrorsEventsTypes } from
    "src/interfaces/OracleMiddleware/ILiquidationRewardsManagerErrorsEventsTypes.sol";

/**
 * @custom:feature The `setRewardsParameters` function of `LiquidationRewardsManager`
 */
contract LiquidationRewardsManagerSetRewardsParameters is
    LiquidationRewardsManagerBaseFixture,
    ILiquidationRewardsManagerErrorsEventsTypes
{
    function setUp() public override {
        super.setUp();
    }

    /**
     * @custom:scenario Call `setRewardsParameters` setter
     * @custom:when The values are within the limits
     * @custom:then It should succeed
     * @custom:and The `getRewardsParameters` should return the newly set values
     * @custom:and The `RewardsParametersUpdated` event should be emitted
     */
    function test_setRewardsParametersWithValidValues() public {
        uint32 gasUsedPerTick = 100_000;
        uint32 otherGasUsed = 200_000;
        uint64 gasPriceLimit = 8000 * (10 ** 9);
        uint16 multiplier = 10;

        vm.expectEmit();
        emit RewardsParametersUpdated(gasUsedPerTick, otherGasUsed, gasPriceLimit, multiplier);
        liquidationRewardsManager.setRewardsParameters(gasUsedPerTick, otherGasUsed, gasPriceLimit, multiplier);

        RewardsParameters memory rewardsParameters = liquidationRewardsManager.getRewardsParameters();

        assertEq(gasUsedPerTick, rewardsParameters.gasUsedPerTick, "The gasUsedPerTick variable was not updated");
        assertEq(otherGasUsed, rewardsParameters.otherGasUsed, "The otherGasUsed variable was not updated");
        assertEq(gasPriceLimit, rewardsParameters.gasPriceLimit, "The gasPriceLimit variable was not updated");
        assertEq(multiplier, rewardsParameters.multiplier, "The multiplier variable was not updated");
    }

    /**
     * @custom:scenario Call `setRewardsParameters` setter
     * @custom:when The caller is not the owner
     * @custom:then It reverts with a OwnableUnauthorizedAccount error
     */
    function test_RevertWhen_setRewardsParametersCallerIsNotTheOwner() public {
        uint32 gasUsedPerTick = 100_000;
        uint32 otherGasUsed = 200_000;
        uint64 gasPriceLimit = 8000 * (10 ** 9);
        uint16 multiplier = 10;

        vm.prank(USER_1);

        // Revert as USER_1 is not the owner
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, USER_1));
        liquidationRewardsManager.setRewardsParameters(gasUsedPerTick, otherGasUsed, gasPriceLimit, multiplier);
    }

    /**
     * @custom:scenario Call `setRewardsParameters` setter
     * @custom:when The value of gasUsedPerTick is bigger than the limit
     * @custom:and The other parameters are within the limits
     * @custom:then It reverts with a LiquidationRewardsManagerGasUsedPerTickTooHigh error
     */
    function test_RevertWhen_setRewardsParametersWithGasUsedPerTickTooHigh() public {
        uint32 gasUsedPerTick = 100_001;
        uint32 otherGasUsed = 200_000;
        uint64 gasPriceLimit = 8000 * (10 ** 9);
        uint16 multiplier = 10;

        // Expect revert when the gas used per tick parameter is too high
        vm.expectRevert(abi.encodeWithSelector(LiquidationRewardsManagerGasUsedPerTickTooHigh.selector, gasUsedPerTick));
        liquidationRewardsManager.setRewardsParameters(gasUsedPerTick, otherGasUsed, gasPriceLimit, multiplier);
    }

    /**
     * @custom:scenario Call `setRewardsParameters` setter
     * @custom:when The value of otherGasUsed is bigger than the limit
     * @custom:and The other parameters are within the limits
     * @custom:then It reverts with a LiquidationRewardsManagerOtherGasUsedTooHigh error
     */
    function test_RevertWhen_setRewardsParametersWithOtherGasUsedTooHigh() public {
        uint32 gasUsedPerTick = 100_000;
        uint32 otherGasUsed = 200_001;
        uint64 gasPriceLimit = 8000 * (10 ** 9);
        uint16 multiplier = 10;

        // Expect revert when the other gas used parameter is too high
        vm.expectRevert(abi.encodeWithSelector(LiquidationRewardsManagerOtherGasUsedTooHigh.selector, otherGasUsed));
        liquidationRewardsManager.setRewardsParameters(gasUsedPerTick, otherGasUsed, gasPriceLimit, multiplier);
    }

    /**
     * @custom:scenario Call `setRewardsParameters` setter
     * @custom:when The value of gasPriceLimit is bigger than the limit
     * @custom:and The other parameters are within the limits
     * @custom:then It reverts with a LiquidationRewardsManagerGasPriceLimitTooHigh error
     */
    function test_RevertWhen_setRewardsParametersWithGasPriceLimitTooHigh() public {
        uint32 gasUsedPerTick = 100_000;
        uint32 otherGasUsed = 200_000;
        uint64 gasPriceLimit = 8000 * (10 ** 9) + 1;
        uint16 multiplier = 10;

        // Expect revert when the gas price limit parameter is too high
        vm.expectRevert(abi.encodeWithSelector(LiquidationRewardsManagerGasPriceLimitTooHigh.selector, gasPriceLimit));
        liquidationRewardsManager.setRewardsParameters(gasUsedPerTick, otherGasUsed, gasPriceLimit, multiplier);
    }

    /**
     * @custom:scenario Call `setRewardsParameters` setter
     * @custom:when The value of multiplier is bigger than the limit
     * @custom:and The other parameters are within the limits
     * @custom:then It reverts with a LiquidationRewardsManagerMultiplierTooHigh error
     */
    function test_RevertWhen_setRewardsParametersWithMultiplierTooHigh() public {
        uint32 gasUsedPerTick = 100_000;
        uint32 otherGasUsed = 200_000;
        uint64 gasPriceLimit = 8000 * (10 ** 9);
        uint16 multiplier = 11;

        // Expect revert when the multiplier is too high
        vm.expectRevert(abi.encodeWithSelector(LiquidationRewardsManagerMultiplierTooHigh.selector, multiplier));
        liquidationRewardsManager.setRewardsParameters(gasUsedPerTick, otherGasUsed, gasPriceLimit, multiplier);
    }
}

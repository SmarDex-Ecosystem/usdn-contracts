// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import {
    ADMIN,
    DEPLOYER,
    PYTH_ETH_USD,
    PYTH_WSTETH_USD,
    SET_EXTERNAL_MANAGER,
    SET_PROTOCOL_PARAMS_MANAGER,
    SET_USDN_PARAMS_MANAGER,
    USER_1,
    USER_2,
    USER_3
} from "../../utils/Constants.sol";
import { UsdnProtocolBaseIntegrationFixture } from "./utils/Fixtures.sol";

import { MockWstEthOracleMiddleware } from "../../../src/OracleMiddleware/mock/MockWstEthOracleMiddleware.sol";
import { ILiquidationRewardsManagerErrorsEventsTypes } from
    "../../../src/interfaces/LiquidationRewardsManager/ILiquidationRewardsManagerErrorsEventsTypes.sol";
import { IBaseRebalancer } from "../../../src/interfaces/Rebalancer/IBaseRebalancer.sol";
import { IRebalancerEvents } from "../../../src/interfaces/Rebalancer/IRebalancerEvents.sol";
import { IUsdnEvents } from "../../../src/interfaces/Usdn/IUsdnEvents.sol";

/**
 * @custom:feature Checking the gas usage of a liquidation
 * @custom:background Given a forked ethereum mainnet chain
 */
contract TestForkUsdnProtocolLiquidationGasUsage is
    UsdnProtocolBaseIntegrationFixture,
    IUsdnEvents,
    IRebalancerEvents
{
    uint256 securityDepositValue;

    function setUp() public {
        params = DEFAULT_PARAMS;
        params.initialDeposit = 101 ether; // needed to trigger rebase
        params.fork = true; // all tests in this contract must be labeled `Fork`
        params.forkWarp = 1_709_794_800; // thu mar 07 2024 07:00:00 UTC
        _setUp(params);

        ILiquidationRewardsManagerErrorsEventsTypes.RewardsParameters memory rewardsParameters =
            liquidationRewardsManager.getRewardsParameters();
        vm.prank(DEPLOYER);
        liquidationRewardsManager.setRewardsParameters(
            rewardsParameters.gasUsedPerTick,
            rewardsParameters.otherGasUsed,
            rewardsParameters.rebaseGasUsed,
            rewardsParameters.rebalancerGasUsed,
            0,
            0,
            0,
            0,
            0.1 ether
        );

        vm.startPrank(USER_1);
        (bool success,) = address(wstETH).call{ value: 1000 ether }("");
        require(success, "Could not mint wstETH to USER_1");
        wstETH.approve(address(protocol), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(USER_2);
        (success,) = address(wstETH).call{ value: 1000 ether }("");
        require(success, "Could not mint wstETH to USER_2");
        wstETH.approve(address(protocol), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(USER_3);
        (success,) = address(wstETH).call{ value: 1000 ether }("");
        require(success, "Could not mint wstETH to USER_3");
        wstETH.approve(address(protocol), type(uint256).max);
        vm.stopPrank();

        securityDepositValue = protocol.getSecurityDepositValue();

        // reduce minimum size to avoid creating a large imbalance in the tests below
        vm.prank(SET_PROTOCOL_PARAMS_MANAGER);
        protocol.setMinLongPosition(0.01 ether);

        // deposit assets in the rebalancer for when we need to trigger it
        wstETH.approve(address(rebalancer), type(uint256).max);
        (success,) = address(wstETH).call{ value: 100 ether }("");
        require(success, "Could not mint wstETH to address(this)");
        rebalancer.initiateDepositAssets(2 ether, address(this));
        skip(rebalancer.getTimeLimits().validationDelay);
        rebalancer.validateDepositAssets();

        // make sure we update _lastPrice when opening positions below
        skip(1 hours);

        /* ------- replace the oracle to setup positions at the desired price ------- */

        (uint256 pythPriceWstETH,,,,) =
            getHermesApiSignature(PYTH_WSTETH_USD, block.timestamp + oracleMiddleware.getValidationDelay());
        uint128 pythPriceNormalized = uint128(pythPriceWstETH * 10 ** 10);

        // use the mock oracle to open positions to avoid hermes calls
        MockWstEthOracleMiddleware mockOracle = new MockWstEthOracleMiddleware(
            address(mockPyth), PYTH_ETH_USD, address(mockChainlinkOnChain), address(wstETH), 1 hours
        );
        vm.prank(SET_EXTERNAL_MANAGER);
        protocol.setOracleMiddleware(mockOracle);
        mockOracle.setWstethMockedPrice(pythPriceNormalized + 1000 ether);
        // turn off pyth signature verification to avoid updating the price feed
        // this allows us to be in the worst-case scenario gas-wise later
        mockOracle.setVerifySignature(false);

        // disable rebase for setup
        vm.startPrank(SET_USDN_PARAMS_MANAGER);
        protocol.setUsdnRebaseThreshold(1000 ether);
        protocol.setTargetUsdnPrice(1000 ether);
        vm.stopPrank();

        /* ---------------------------- set up positions ---------------------------- */

        uint128 minLongPosition = uint128(protocol.getMinLongPosition());
        uint256 maxLeverage = protocol.getMaxLeverage();
        vm.prank(USER_1);
        protocol.initiateOpenPosition{ value: securityDepositValue }(
            minLongPosition,
            pythPriceNormalized + 200 ether,
            maxLeverage,
            USER_1,
            USER_1,
            NO_PERMIT2,
            hex"beef",
            EMPTY_PREVIOUS_DATA
        );
        vm.prank(USER_2);
        protocol.initiateOpenPosition{ value: securityDepositValue }(
            minLongPosition,
            pythPriceNormalized + 150 ether,
            maxLeverage,
            USER_2,
            USER_2,
            NO_PERMIT2,
            hex"beef",
            EMPTY_PREVIOUS_DATA
        );
        vm.prank(USER_3);
        protocol.initiateOpenPosition{ value: securityDepositValue }(
            minLongPosition,
            pythPriceNormalized + 100 ether,
            maxLeverage,
            USER_3,
            USER_3,
            NO_PERMIT2,
            hex"beef",
            EMPTY_PREVIOUS_DATA
        );
        _waitDelay();
        vm.prank(USER_1);
        protocol.validateOpenPosition(USER_1, hex"beef", EMPTY_PREVIOUS_DATA);
        vm.prank(USER_2);
        protocol.validateOpenPosition(USER_2, hex"beef", EMPTY_PREVIOUS_DATA);
        vm.prank(USER_3);
        protocol.validateOpenPosition(USER_3, hex"beef", EMPTY_PREVIOUS_DATA);

        // put the original oracle back
        vm.prank(SET_EXTERNAL_MANAGER);
        protocol.setOracleMiddleware(oracleMiddleware);
    }

    /**
     * @custom:scenario The gas usage of UsdnProtocolActions.liquidate(bytes,uint16) matches the values set in
     * LiquidationRewardsManager.getRewardsParameters
     * @custom:given There are one or more ticks that can be liquidated
     * @custom:and No rebase occurs
     * @custom:when A liquidator calls the function `liquidate`
     * @custom:then The gas usage matches the LiquidationRewardsManager parameters
     */
    function test_ForkGasUsageOfLiquidateFunction() public {
        _forkGasUsageHelper(false);
    }

    /**
     * @custom:scenario The gas usage of UsdnProtocolActions.liquidate(bytes,uint16) matches the values set in
     * LiquidationRewardsManager.getRewardsParameters
     * @custom:given There are one or more ticks that can be liquidated
     * @custom:and A rebase occurs
     * @custom:when A liquidator calls the function `liquidate`
     * @custom:then The gas usage matches the LiquidationRewardsManager parameters
     */
    function test_ForkGasUsageOfLiquidateFunctionRebase() public {
        _forkGasUsageHelper(true);
    }

    function _forkGasUsageHelper(bool withRebase) public {
        // disable rebalancer
        vm.prank(SET_EXTERNAL_MANAGER);
        protocol.setRebalancer(IBaseRebalancer(address(0)));

        uint256[] memory gasUsedArray = new uint256[](3);
        ILiquidationRewardsManagerErrorsEventsTypes.RewardsParameters memory rewardsParameters =
            liquidationRewardsManager.getRewardsParameters();

        skip(1 minutes);
        (,,,, bytes memory data) = getHermesApiSignature(PYTH_ETH_USD, block.timestamp);
        uint256 oracleFee = oracleMiddleware.validationCost(data, ProtocolAction.Liquidation);

        // if required, enable rebase
        if (withRebase) {
            vm.startPrank(SET_USDN_PARAMS_MANAGER);
            protocol.setTargetUsdnPrice(1 ether);
            protocol.setUsdnRebaseThreshold(1 ether);
            vm.stopPrank();
        }

        // take a snapshot to re-do liquidations with different iterations
        uint256 snapshotId = vm.snapshot();
        for (uint16 ticksToLiquidate = 1; ticksToLiquidate <= 3; ++ticksToLiquidate) {
            if (withRebase) {
                // sanity check, make sure a rebase was executed
                vm.expectEmit(false, false, false, false);
                emit Rebase(0, 0);
            }

            uint256 startGas = gasleft();
            LiqTickInfo[] memory liquidatedTicks = protocol.liquidate{ value: oracleFee }(data, ticksToLiquidate);
            uint256 gasUsed = startGas - gasleft();
            gasUsedArray[ticksToLiquidate - 1] = gasUsed;

            // make sure the expected amount of computation was executed
            assertEq(
                liquidatedTicks.length,
                ticksToLiquidate,
                "We expect 1, 2 or 3 positions liquidated depending on the iteration"
            );

            // cancel the liquidation so it's available again
            vm.revertTo(snapshotId);
        }

        // calculate the average gas used exclusively by a loop of tick liquidation
        uint256 averageGasUsedPerTick = (gasUsedArray[1] - gasUsedArray[0] + gasUsedArray[2] - gasUsedArray[1]) / 2;
        // calculate the average gas used by everything BUT loops of tick liquidation
        uint256 averageOtherGasUsed =
            (gasUsedArray[0] + gasUsedArray[1] + gasUsedArray[2] - (averageGasUsedPerTick * 6)) / 3;

        // check that the gas usage per tick matches the gasUsedPerTick parameter in the LiquidationRewardsManager
        assertEq(
            averageGasUsedPerTick,
            rewardsParameters.gasUsedPerTick,
            "The result should match the gasUsedPerTick parameter set in LiquidationRewardsManager's constructor"
        );
        // check that the other gas usage matches the otherGasUsed parameter in the LiquidationRewardsManager
        uint256 otherGasUsed = rewardsParameters.otherGasUsed;
        if (withRebase) {
            otherGasUsed += rewardsParameters.rebaseGasUsed;
        }
        assertEq(
            averageOtherGasUsed,
            otherGasUsed,
            "The result should match the otherGasUsed(+rebaseGasUsed) parameter set in LiquidationRewardsManager's constructor"
        );
    }

    /**
     * @custom:scenario The gas usage of UsdnProtocolActions.liquidate(bytes,uint16) matches the values set in
     * LiquidationRewardsManager.getRewardsParameters
     * @custom:given There are 3 ticks that can be liquidated
     * @custom:and A rebalancer trigger occurs
     * @custom:when A liquidator calls the function `liquidate`
     * @custom:then The gas usage matches the LiquidationRewardsManager parameters
     */
    function test_ForkGasUsageOfLiquidateFunctionWithRebalancer() public {
        uint256[] memory gasUsedArray = new uint256[](2);
        ILiquidationRewardsManagerErrorsEventsTypes.RewardsParameters memory rewardsParameters =
            liquidationRewardsManager.getRewardsParameters();

        skip(1 minutes);
        (,,,, bytes memory data) = getHermesApiSignature(PYTH_ETH_USD, block.timestamp);
        uint256 oracleFee = oracleMiddleware.validationCost(data, ProtocolAction.Liquidation);

        // take a snapshot to re-do liquidations with different iterations
        uint256 snapshotId = vm.snapshot();
        for (uint256 i = 0; i < 2; ++i) {
            uint16 ticksToLiquidate = 3;

            // on the second iteration, enable the rebalancer
            if (i == 1) {
                // enable rebalancer
                vm.prank(SET_PROTOCOL_PARAMS_MANAGER);
                protocol.setExpoImbalanceLimits(5000, 0, 10_000, 1, 1, -4900);

                // sanity check, make sure the rebalancer was triggered
                vm.expectEmit(false, false, false, false);
                emit PositionVersionUpdated(0, 0, 0, PositionId(0, 0, 0));
            }

            uint256 startGas = gasleft();
            LiqTickInfo[] memory liquidatedTicks = protocol.liquidate{ value: oracleFee }(data, ticksToLiquidate);
            uint256 gasUsed = startGas - gasleft();
            gasUsedArray[i] = gasUsed;

            // make sure the expected amount of computation was executed
            assertEq(liquidatedTicks.length, ticksToLiquidate, "We expect 3 positions liquidated");

            // cancel the liquidation so it's available again
            vm.revertTo(snapshotId);
        }

        // calculate the gas used by the rebalancer trigger
        uint256 gasUsedByRebalancer = gasUsedArray[1] - gasUsedArray[0];

        // check that the gas usage per tick matches the gasUsedPerTick parameter in the LiquidationRewardsManager
        assertEq(
            gasUsedByRebalancer,
            rewardsParameters.rebalancerGasUsed,
            "The result should match the rebalancerGasUsed parameter set in LiquidationRewardsManager's constructor"
        );
    }
}

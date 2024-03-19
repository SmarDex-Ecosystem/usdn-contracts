// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { UsdnProtocolBaseIntegrationFixture } from "test/integration/UsdnProtocol/utils/Fixtures.sol";
import { DEPLOYER, USER_1, USER_2, USER_3, PYTH_STETH_USD, PYTH_WSTETH_USD } from "test/utils/Constants.sol";

import { ILiquidationRewardsManagerErrorsEventsTypes } from
    "src/interfaces/OracleMiddleware/ILiquidationRewardsManagerErrorsEventsTypes.sol";
import { ProtocolAction } from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import { IUsdnEvents } from "src/interfaces/Usdn/IUsdnEvents.sol";
import { MockWstEthOracleMiddleware } from "src/OracleMiddleware/mock/MockWstEthOracleMiddleware.sol";

/**
 * @custom:feature Checking the gas usage of a liquidation.
 * @custom:background Given a forked ethereum mainnet chain
 */
contract ForkUsdnProtocolLiquidationGasUsageTest is UsdnProtocolBaseIntegrationFixture, IUsdnEvents {
    function setUp() public {
        params = DEFAULT_PARAMS;
        params.initialLong = 10 ether;
        params.initialDeposit = 100 ether;
        params.fork = true; // all tests in this contract must be labelled `Fork`
        params.forkWarp = 1_709_794_800; // Thu Mar 07 2024 07:00:00 UTC
        _setUp(params);

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
    }

    /**
     * @custom:scenario The gas usage of UsdnProtocolActions.liquidate(bytes,uint16) matches the values set in
     * LiquidationRewardsManager.getRewardsParameters
     * @custom:given There are one or more ticks that can be liquidated
     * @custom:and No rebase occurs
     * @custom:when A liquidator calls the function liquidate
     * @custom:then The gas usage matches the LiquidationRewardsManager parameters
     */
    function test_forkGasUsageOfLiquidateFunction() public {
        _forkGasUsageHelper(false);
    }

    /**
     * @custom:scenario The gas usage of UsdnProtocolActions.liquidate(bytes,uint16) matches the values set in
     * LiquidationRewardsManager.getRewardsParameters
     * @custom:given There are one or more ticks that can be liquidated
     * @custom:and A rebase occurs
     * @custom:when A liquidator calls the function liquidate
     * @custom:then The gas usage matches the LiquidationRewardsManager parameters
     */
    function test_forkGasUsageOfLiquidateFunctionRebase() public {
        _forkGasUsageHelper(true);
    }

    function _forkGasUsageHelper(bool withRebase) public {
        (uint256 pythPriceWstETH,,,,) =
            getHermesApiSignature(PYTH_WSTETH_USD, block.timestamp + oracleMiddleware.getValidationDelay());
        uint128 pythPriceNormalized = uint128(pythPriceWstETH * 10 ** 10);

        // Use the mock oracle to open positions to avoid hermes calls
        MockWstEthOracleMiddleware mockOracle = new MockWstEthOracleMiddleware(
            address(mockPyth), PYTH_STETH_USD, address(mockChainlinkOnChain), address(wstETH), 1 hours
        );
        vm.prank(DEPLOYER);
        protocol.setOracleMiddleware(mockOracle);
        mockOracle.setWstethMockedPrice(pythPriceNormalized + 1000 ether);
        // Turn off pyth signature verification to avoid updating the price feed
        // This allows us to be in the worst case scenario gas wise later
        mockOracle.setVerifySignature(false);

        // Disable rebase for setup
        vm.startPrank(DEPLOYER);
        protocol.setUsdnRebaseThreshold(1000 ether);
        protocol.setTargetUsdnPrice(1000 ether);
        vm.stopPrank();

        /* ---------------------------- Set up positions ---------------------------- */

        vm.prank(USER_1);
        protocol.initiateOpenPosition(1 ether, pythPriceNormalized + 150e18, hex"beef", EMPTY_PREVIOUS_DATA);
        vm.prank(USER_2);
        protocol.initiateOpenPosition(1 ether, pythPriceNormalized + 100e18, hex"beef", EMPTY_PREVIOUS_DATA);
        vm.prank(USER_3);
        protocol.initiateOpenPosition(1 ether, pythPriceNormalized + 50e18, hex"beef", EMPTY_PREVIOUS_DATA);
        _waitDelay();
        vm.prank(USER_1);
        protocol.validateOpenPosition(hex"beef", EMPTY_PREVIOUS_DATA);
        vm.prank(USER_2);
        protocol.validateOpenPosition(hex"beef", EMPTY_PREVIOUS_DATA);
        vm.prank(USER_3);
        protocol.validateOpenPosition(hex"beef", EMPTY_PREVIOUS_DATA);

        /* ---------------------------- Start the checks ---------------------------- */
        // Put the original oracle back
        vm.prank(DEPLOYER);
        protocol.setOracleMiddleware(oracleMiddleware);

        uint256[] memory gasUsedArray = new uint256[](3);
        ILiquidationRewardsManagerErrorsEventsTypes.RewardsParameters memory rewardsParameters =
            liquidationRewardsManager.getRewardsParameters();

        skip(1 minutes);
        (,,,, bytes memory data) = getHermesApiSignature(PYTH_STETH_USD, block.timestamp);
        uint256 oracleFee = oracleMiddleware.validationCost(data, ProtocolAction.Liquidation);

        // If required, enable rebase
        if (withRebase) {
            vm.startPrank(DEPLOYER);
            protocol.setTargetUsdnPrice(1 ether);
            protocol.setUsdnRebaseThreshold(1 ether);
            vm.stopPrank();
        }

        // Take a snapshot to re-do liquidations with different iterations
        uint256 snapshotId = vm.snapshot();
        for (uint16 ticksToLiquidate = 1; ticksToLiquidate <= 3; ++ticksToLiquidate) {
            if (withRebase) {
                // Sanity check, make sure a rebase was executed
                vm.expectEmit(false, false, false, false);
                emit Rebase(0, 0);
            }

            // Get a price that liquidates `ticksToLiquidate` ticks
            uint256 startGas = gasleft();
            uint256 positionsLiquidated = protocol.liquidate{ value: oracleFee }(data, ticksToLiquidate);
            uint256 gasUsed = startGas - gasleft();
            gasUsedArray[ticksToLiquidate - 1] = gasUsed;

            // Make sure the expected amount of computation was executed
            assertEq(
                positionsLiquidated,
                ticksToLiquidate,
                "We expect 1, 2 or 3 positions liquidated depending on the iteration"
            );

            // Cancel the liquidation so it's available again
            vm.revertTo(snapshotId);
        }

        // Calculate the average gas used exclusively by a loop of tick liquidation
        uint256 averageGasUsedPerTick = (gasUsedArray[1] - gasUsedArray[0] + gasUsedArray[2] - gasUsedArray[1]) / 2;
        // Calculate the average gas used by everything BUT loops of tick liquidation
        uint256 averageOtherGasUsed =
            (gasUsedArray[0] + gasUsedArray[1] + gasUsedArray[2] - (averageGasUsedPerTick * 6)) / 3;

        // Check that the gas usage per tick matches the gasUsedPerTick parameter in the LiquidationRewardsManager
        assertEq(
            averageGasUsedPerTick,
            rewardsParameters.gasUsedPerTick,
            "The result should match the gasUsedPerTick parameter set in LiquidationRewardsManager's constructor"
        );
        // Check that the other gas usage matches the otherGasUsed parameter in the LiquidationRewardsManager
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
}

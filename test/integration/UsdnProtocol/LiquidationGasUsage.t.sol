// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { UsdnProtocolBaseIntegrationFixture } from "test/integration/UsdnProtocol/utils/Fixtures.sol";
import { PYTH_STETH_USD, WSTETH } from "test/utils/Constants.sol";
import {
    PYTH_DATA,
    PYTH_DATA_STETH_PRICE,
    PYTH_DATA_TIMESTAMP
} from "test/integration/OracleMiddleware/utils/Constants.sol";

import { ILiquidationRewardsManagerErrorsEventsTypes } from
    "src/interfaces/OracleMiddleware/ILiquidationRewardsManagerErrorsEventsTypes.sol";
import { MockWstEthOracleMiddleware } from "src/OracleMiddleware/mock/MockWstEthOracleMiddleware.sol";
import { ProtocolAction } from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";

/**
 * @custom:feature Checking the gas usage of a liquidation.
 * @custom:background Given a forked ethereum mainnet chain
 */
contract ForkUsdnProtocolLiquidationGasUsageTest is UsdnProtocolBaseIntegrationFixture {
    MockWstEthOracleMiddleware mockOracle;

    function setUp() public override {
        params = DEFAULT_PARAMS;
        params.fork = true; // all tests in this contract must be labelled `Fork`
        _setUp(params);

        (bool success,) = address(WST_ETH).call{ value: 1000 ether }("");
        require(success, "Could not mint wstETH to test contract");
        WST_ETH.approve(address(protocol), type(uint256).max);
    }

    /**
     * @custom:scenario The gas usage of UsdnProtocolActions.liquidate(bytes,uint16) matches the values set in
     * LiquidationRewardsManager.getRewardsParameters
     * @custom:given There are one or more ticks that can be liquidated
     * @custom:when A liquidator calls the function liquidate
     * @custom:then The gas usage matches the LiquidationRewardsManager parameters
     */
    function test_gasUsageOfLiquidateFunction() public {
        (uint256 pythPrice,, uint256 pythTimestamp, bytes memory data) = getMockedPythSignature();

        // Use the mock oracle to open positions to avoid hermes calls
        mockOracle = new MockWstEthOracleMiddleware(
            address(pyth), PYTH_STETH_USD, address(chainlinkOnChain), address(WST_ETH), 1 hours
        );
        protocol.setOracleMiddleware(mockOracle);
        mockOracle.setWstethMockedPrice((pythPrice + 1000e8) * 10 ** 10);
        // Turn off pyth signature verification to avoid updating the price feed
        // This allows us to be in the worst case scenario gas wise later
        mockOracle.toggleVerifySignature();

        uint256 oracleFee = 1;
        uint128 futurePythPrice = uint128(pythPrice + 500e8) * 10 ** 10;

        /* ---------------------------- Set up position 1 --------------------------- */
        vm.warp(pythTimestamp - wstethMiddleware.validationDelay());
        protocol.initiateOpenPosition(1 ether, futurePythPrice + 150e18, data, "");
        protocol.validateOpenPosition(data, "");

        /* ---------------------------- Set up position 2 --------------------------- */
        vm.warp(pythTimestamp - wstethMiddleware.validationDelay());
        protocol.initiateOpenPosition(1 ether, futurePythPrice + 100e18, data, "");
        protocol.validateOpenPosition(data, "");

        /* ---------------------------- Set up position 3 --------------------------- */
        vm.warp(pythTimestamp - wstethMiddleware.validationDelay());
        protocol.initiateOpenPosition(1 ether, futurePythPrice + 50e18, data, "");
        protocol.validateOpenPosition(data, "");

        /* ---------------------------- Start the checks ---------------------------- */
        // Do not use the mocked price anymore for accurate gas usage
        mockOracle.setWstethMockedPrice(0);
        // Enable the signature verification again
        mockOracle.toggleVerifySignature();
        ILiquidationRewardsManagerErrorsEventsTypes.RewardsParameters memory rewardsParameters =
            liquidationRewardsManager.getRewardsParameters();
        vm.warp(pythTimestamp);

        // Take a snapshot to re-do liquidations with different iterations
        uint256 snapshotId = vm.snapshot();

        uint256[] memory gasUsedArray = new uint256[](3);
        for (uint16 ticksToLiquidate = 1; ticksToLiquidate <= 3; ++ticksToLiquidate) {
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
        assertEq(
            averageOtherGasUsed,
            rewardsParameters.otherGasUsed,
            "The result should match the otherGasUsed parameter set in LiquidationRewardsManager's constructor"
        );
    }

    // handle oracle fee refunds
    receive() external payable { }
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { LiquidationRewardsManagerBaseFixture } from "test/unit/OracleMiddleware/utils/Fixtures.sol";
import { LiquidationRewardsManager } from "src/OracleMiddleware/LiquidationRewardsManager.sol";

/**
 * @custom:feature The `getLiquidationRewards` function of `LiquidationRewardsManager`
 */
contract LiquidationRewardsManagerGetLiquidationRewards is LiquidationRewardsManagerBaseFixture {
    function setUp() public override {
        super.setUp();
        mockChainlinkOnChain.updateLastPublishTime(block.timestamp);
    }

    /**
     * @custom:scenario Call `getLiquidationRewards` function
     * @custom:when 1 tick was liquidated
     * @custom:and The tx.gasprice and oracle gas price feed are equals
     * @custom:and They are both below the gas price limit
     * @custom:and The exchange rate for stETH per wstETH is 1.15
     * @custom:then It should return an amount of wstETH based on the gas used by
     * UsdnProtocolActions.liquidate(bytes,uint16)
     */
    function test_getLiquidationRewardsFor1Tick() public {
        uint256 rewards = liquidationRewardsManager.getLiquidationRewards(1, 0);

        assertEq(rewards, 6_435_492_000_000_000);
    }

    /**
     * @custom:scenario Call `getLiquidationRewards` function
     * @custom:when No ticks were liquidated
     * @custom:then It should return 0 as we only give rewards on successful liquidations
     */
    function test_getLiquidationRewardsFor0Tick() public {
        uint256 rewards = liquidationRewardsManager.getLiquidationRewards(0, 0);

        assertEq(rewards, 0, "No rewards should be granted if there were no liquidations");
    }

    /**
     * @custom:scenario Call `getLiquidationRewards` function
     * @custom:when 3 ticks were liquidated
     * @custom:and The tx.gasprice and oracle gas price feed are equals
     * @custom:and They are both below the gas price limit
     * @custom:and The exchange rate for stETH per wstETH is 1.15
     * @custom:then It should return more wstETH than for 1 tick as more gas was used by
     * UsdnProtocolActions.liquidate(bytes,uint16)
     */
    function test_getLiquidationRewardsFor3Ticks() public {
        uint256 rewards = liquidationRewardsManager.getLiquidationRewards(3, 0);

        assertEq(rewards, 10_263_060_000_000_000, "The wrong amount of rewards was given");

        assertNotEq(
            rewards,
            liquidationRewardsManager.getLiquidationRewards(1, 0),
            "Differents amount of ticks liquidated shouldn't give the same amount of rewards"
        );
    }

    /**
     * @custom:scenario Call `getLiquidationRewards` function
     * @custom:when The oracle gas price feed is lower than the tx.gasprice
     * @custom:and They are both below the gas price limit
     * @custom:and 1 tick was liquidated
     * @custom:and The exchange rate for stETH per wstETH is 1.15
     * @custom:then It should return an amount of wstETH based on the gas used by
     * UsdnProtocolActions.liquidate(bytes,uint16) and the gas price from the oracle
     */
    function test_getLiquidationRewardsWithOracleGasPrice() public {
        mockChainlinkOnChain.setLatestRoundData(1, 15 gwei, block.timestamp, 1);
        uint256 rewards = liquidationRewardsManager.getLiquidationRewards(1, 0);

        assertEq(rewards, 3_217_746_000_000_000);
    }

    /**
     * @custom:scenario Call `getLiquidationRewards` function
     * @custom:when The tx.gasprice is lower than the oracle gas price feed
     * @custom:and They are both below the gas price limit
     * @custom:and 1 tick was liquidated
     * @custom:and The exchange rate for stETH per wstETH is 1.15
     * @custom:then It should return an amount of wstETH based on the gas used by
     * UsdnProtocolActions.liquidate(bytes,uint16) and the gas price from tx.gasPrice
     */
    function test_getLiquidationRewardsWithTxGasPrice() public {
        vm.txGasPrice(20 gwei);
        uint256 rewards = liquidationRewardsManager.getLiquidationRewards(1, 0);

        assertEq(rewards, 4_290_328_000_000_000);
    }

    /**
     * @custom:scenario Call `getLiquidationRewards` function
     * @custom:when The tx.gasprice is lower than the oracle gas price feed
     * @custom:and They are both above the gas price limit
     * @custom:and 1 tick was liquidated
     * @custom:and The exchange rate for stETH per wstETH is 1.15
     * @custom:then It should return an amount of wstETH calculated with a gas price equal to the limit
     */
    function test_getLiquidationRewardsWithTxGasPriceAndAboveTheLimit() public {
        vm.txGasPrice(1001 gwei);
        mockChainlinkOnChain.setLatestRoundData(1, 2000 gwei, block.timestamp, 1);
        uint256 rewards = liquidationRewardsManager.getLiquidationRewards(1, 0);

        // With a gas price at 1001 gwei, the result without the limit should have been 180_389_809_600_000_000
        assertEq(rewards, 214_516_400_000_000_000);
    }

    /**
     * @custom:scenario Call `getLiquidationRewards` function
     * @custom:when The oracle gas price feed is lower than tx.gasprice
     * @custom:and They are both above the gas price limit
     * @custom:and 1 tick was liquidated
     * @custom:and The exchange rate for stETH per wstETH is 1.15
     * @custom:then It should return an amount of wstETH calculated with a gas price equal to the limit
     */
    function test_getLiquidationRewardsWithOracleAndAboveTheLimit() public {
        vm.txGasPrice(2000 gwei);
        mockChainlinkOnChain.setLatestRoundData(1, 1001 gwei, block.timestamp, 1);
        uint256 rewards = liquidationRewardsManager.getLiquidationRewards(1, 0);

        // With a gas price at 1001 gwei, the result without the limit should have been 180_389_809_600_000_000
        assertEq(rewards, 214_516_400_000_000_000);
    }

    /**
     * @custom:scenario Call `getLiquidationRewards` function
     * @custom:when The oracle returns -1
     * @custom:then It should return 0 to avoid relying solely on tx.gasprice
     */
    function test_getLiquidationRewardsWithOracleGasPriceFeedBroken() public {
        mockChainlinkOnChain.toggleRevert();
        uint256 rewards = liquidationRewardsManager.getLiquidationRewards(1, 0);

        assertEq(rewards, 0, "The function should return 0");
    }
}

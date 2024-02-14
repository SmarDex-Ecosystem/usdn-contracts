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
     * @custom:then It should return an amount of wstETH
     */
    function test_getLiquidationRewardsFor1Tick() public {
        uint256 rewards = liquidationRewardsManager.getLiquidationRewards(1, 0);

        assertEq(rewards, 5_406_288_000_000_000);
    }

    /**
     * @custom:scenario Call `getLiquidationRewards` function
     * @custom:when No ticks were liquidated
     * @custom:then It should return 0 as no liquidations means no rewards
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
     * @custom:then It should return an amount of wstETH
     */
    function test_getLiquidationRewardsFor3Ticks() public {
        uint256 rewards = liquidationRewardsManager.getLiquidationRewards(3, 0);

        assertEq(rewards, 9_224_886_000_000_000);
    }

    /**
     * @custom:scenario Call `getLiquidationRewards` function
     * @custom:when The oracle gas price feed is lower than the tx.gasprice
     * @custom:and They are both below the gas price limit
     * @custom:and 1 tick was liquidated
     * @custom:and The exchange rate for stETH per wstETH is 1.15
     * @custom:then It should return an amount of wstETH
     */
    function test_getLiquidationRewardsWithOracleGasPrice() public {
        mockChainlinkOnChain.setLatestRoundData(1, 15 * (10 ** 9), block.timestamp, 1);
        uint256 rewards = liquidationRewardsManager.getLiquidationRewards(1, 0);

        assertEq(rewards, 2_703_144_000_000_000);
    }

    /**
     * @custom:scenario Call `getLiquidationRewards` function
     * @custom:when The tx.gasprice is lower than the oracle gas price feed
     * @custom:and They are both below the gas price limit
     * @custom:and 1 tick was liquidated
     * @custom:and The exchange rate for stETH per wstETH is 1.15
     * @custom:then It should return an amount of wstETH
     */
    function test_getLiquidationRewardsWithTxGasPrice() public {
        vm.txGasPrice(20 * (10 ** 9));
        uint256 rewards = liquidationRewardsManager.getLiquidationRewards(1, 0);

        assertEq(rewards, 3_604_192_000_000_000);
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
        vm.txGasPrice(1001 * (10 ** 9));
        mockChainlinkOnChain.setLatestRoundData(1, 2000 * (10 ** 9), block.timestamp, 1);
        uint256 rewards = liquidationRewardsManager.getLiquidationRewards(1, 0);

        // With a gas price at 1001 gwei, the result without the limit should have been 180_389_809_600_000_000
        assertEq(rewards, 180_209_600_000_000_000);
    }

    /**
     * @custom:scenario Call `getLiquidationRewards` function
     * @custom:when The oracle gas price feed is lower than tx.gasprice
     * @custom:and They are both above the gas price limit
     * @custom:and 1 tick was liquidated
     * @custom:and The exchange rate for stETH per wstETH is 1.15
     * @custom:then It should return an amount of wstETH calculated with a gas price equal to the limit
     */
    function test_getLiquidationRewardsWithOacleGasPriceFeedAndAboveTheLimit() public {
        vm.txGasPrice(2000 * (10 ** 9));
        mockChainlinkOnChain.setLatestRoundData(1, 1001 * (10 ** 9), block.timestamp, 1);
        uint256 rewards = liquidationRewardsManager.getLiquidationRewards(1, 0);

        // With a gas price at 1001 gwei, the result without the limit should have been 180_389_809_600_000_000
        assertEq(rewards, 180_209_600_000_000_000);
    }

    /**
     * @custom:scenario Call `getLiquidationRewards` function
     * @custom:when The oracle returns -1
     * @custom:then It should return 0 to avoid relying solely on tx.gasprice
     */
    function test_getLiquidationRewardsWithOacleGasPriceFeedBroken() public {
        vm.txGasPrice(2000 * (10 ** 9));
        mockChainlinkOnChain.toggleRevert();
        uint256 rewards = liquidationRewardsManager.getLiquidationRewards(1, 0);

        assertEq(rewards, 0, "The function should return 0");
    }
}

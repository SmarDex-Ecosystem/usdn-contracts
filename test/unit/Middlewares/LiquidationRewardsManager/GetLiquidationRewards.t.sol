// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { LiquidationRewardsManagerBaseFixture } from "../utils/Fixtures.sol";

import { IUsdnProtocolTypes as Types } from "../../../../src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";

/**
 * @custom:feature The `getLiquidationRewards` function of `LiquidationRewardsManager`
 */
contract TestLiquidationRewardsManagerGetLiquidationRewards is LiquidationRewardsManagerBaseFixture {
    function setUp() public override {
        super.setUp();
        mockChainlinkOnChain.setLastPublishTime(block.timestamp);

        // Change The rewards calculations parameters to not be dependent of the initial values
        liquidationRewardsManager.setRewardsParameters(10_000, 30_000, 20_000, 10_000, 1000 gwei, 30_000);

        // Puts the gas at 30 gwei
        mockChainlinkOnChain.setLatestRoundData(1, 30 gwei, block.timestamp, 1);
        vm.txGasPrice(30 gwei);
    }

    /**
     * @custom:scenario Call `getLiquidationRewards` when 1 tick was liquidated
     * @custom:when 1 tick was liquidated
     * @custom:and The tx.gasprice and oracle gas price feed are equals
     * @custom:and They are both below the gas price limit
     * @custom:and The exchange rate for stETH per wstETH is 1.15
     * @custom:then It should return an amount of wstETH based on the gas used by
     * UsdnProtocolActions.liquidate(bytes,uint16)
     */
    function test_getLiquidationRewardsFor1Tick() public view {
        uint256 rewards =
            liquidationRewardsManager.getLiquidationRewards(1, 0, false, false, Types.ProtocolAction.None, "", "");
        assertEq(rewards, 2_794_500_000_000_000, "without rebase");
        rewards = liquidationRewardsManager.getLiquidationRewards(1, 0, true, false, Types.ProtocolAction.None, "", "");
        assertEq(rewards, 3_484_500_000_000_000, "with rebase");
        rewards =
            liquidationRewardsManager.getLiquidationRewards(1, 0, true, false, Types.ProtocolAction.None, "", hex"beef");
        assertEq(rewards, 3_484_500_000_000_000, "with rebase and price data");
        rewards = liquidationRewardsManager.getLiquidationRewards(1, 0, false, true, Types.ProtocolAction.None, "", "");
        assertEq(rewards, 3_139_500_000_000_000, "with rebalancer trigger");
    }

    /**
     * @custom:scenario Call `getLiquidationRewards` when 0 ticks were liquidated
     * @custom:when No ticks were liquidated
     * @custom:then It should return 0 as we only give rewards on successful liquidations
     */
    function test_getLiquidationRewardsFor0Tick() public view {
        uint256 rewards =
            liquidationRewardsManager.getLiquidationRewards(0, 0, false, false, Types.ProtocolAction.None, "", "");
        assertEq(rewards, 0, "without rebase");
        rewards = liquidationRewardsManager.getLiquidationRewards(0, 0, true, false, Types.ProtocolAction.None, "", "");
        assertEq(rewards, 0, "with rebase");
        rewards = liquidationRewardsManager.getLiquidationRewards(0, 0, false, true, Types.ProtocolAction.None, "", "");
        assertEq(rewards, 0, "with rebalancer trigger");
    }

    /**
     * @custom:scenario Call `getLiquidationRewards` when 3 ticks were liquidated
     * @custom:when 3 ticks were liquidated
     * @custom:and The tx.gasprice and oracle gas price feed are equals
     * @custom:and They are both below the gas price limit
     * @custom:and The exchange rate for stETH per wstETH is 1.15
     * @custom:then It should return more wstETH than for 1 tick as more gas was used by
     * UsdnProtocolActions.liquidate(bytes,uint16)
     */
    function test_getLiquidationRewardsFor3Ticks() public view {
        uint256 rewards =
            liquidationRewardsManager.getLiquidationRewards(3, 0, false, false, Types.ProtocolAction.None, "", "");
        assertEq(rewards, 4_864_500_000_000_000, "The wrong amount of rewards was given");
        assertGt(
            rewards,
            liquidationRewardsManager.getLiquidationRewards(1, 0, false, false, Types.ProtocolAction.None, "", ""),
            "More rewards should be given if more ticks are liquidated"
        );
        rewards = liquidationRewardsManager.getLiquidationRewards(3, 0, true, false, Types.ProtocolAction.None, "", "");
        assertEq(rewards, 5_554_500_000_000_000, "with rebase - expected rewards");
        assertGt(
            rewards,
            liquidationRewardsManager.getLiquidationRewards(1, 0, true, false, Types.ProtocolAction.None, "", ""),
            "with rebase - greater than fewer ticks"
        );
        rewards = liquidationRewardsManager.getLiquidationRewards(3, 0, false, true, Types.ProtocolAction.None, "", "");
        assertEq(rewards, 5_209_500_000_000_000, "with rebalancer trigger - expected rewards");
        assertGt(
            rewards,
            liquidationRewardsManager.getLiquidationRewards(1, 0, false, true, Types.ProtocolAction.None, "", ""),
            "with rebalancer trigger - greater than fewer ticks"
        );
    }

    /**
     * @custom:scenario Call `getLiquidationRewards` when the oracle's value is lower than tx.gasPrice
     * @custom:when The oracle gas price feed is lower than the tx.gasprice
     * @custom:and They are both below the gas price limit
     * @custom:and 1 tick was liquidated
     * @custom:and The exchange rate for stETH per wstETH is 1.15
     * @custom:then It should return an amount of wstETH based on the gas used by
     * UsdnProtocolActions.liquidate(bytes,uint16) and the gas price from the oracle
     */
    function test_getLiquidationRewardsWithOracleGasPrice() public {
        mockChainlinkOnChain.setLatestRoundData(1, 15 gwei, block.timestamp, 1);

        uint256 rewards =
            liquidationRewardsManager.getLiquidationRewards(1, 0, false, false, Types.ProtocolAction.None, "", "");
        assertEq(rewards, 1_397_250_000_000_000, "without rebase");

        rewards = liquidationRewardsManager.getLiquidationRewards(1, 0, true, false, Types.ProtocolAction.None, "", "");
        assertEq(rewards, 1_742_250_000_000_000, "with rebase");

        rewards = liquidationRewardsManager.getLiquidationRewards(1, 0, false, true, Types.ProtocolAction.None, "", "");
        assertEq(rewards, 1_569_750_000_000_000, "with rebalancer trigger");
    }

    /**
     * @custom:scenario Call `getLiquidationRewards` when tx.gasPrice is lower than the oracle's value
     * @custom:when The tx.gasprice is lower than the oracle gas price feed
     * @custom:and They are both below the gas price limit
     * @custom:and 1 tick was liquidated
     * @custom:and The exchange rate for stETH per wstETH is 1.15
     * @custom:then It should return an amount of wstETH based on the gas used by
     * UsdnProtocolActions.liquidate(bytes,uint16) and the gas price from tx.gasPrice
     */
    function test_getLiquidationRewardsWithTxGasPrice() public {
        vm.txGasPrice(20 gwei);

        uint256 rewards =
            liquidationRewardsManager.getLiquidationRewards(1, 0, false, false, Types.ProtocolAction.None, "", "");
        assertEq(rewards, 1_863_000_000_000_000, "without rebase");

        rewards = liquidationRewardsManager.getLiquidationRewards(1, 0, true, false, Types.ProtocolAction.None, "", "");
        assertEq(rewards, 2_323_000_000_000_000, "with rebase");

        rewards = liquidationRewardsManager.getLiquidationRewards(1, 0, false, true, Types.ProtocolAction.None, "", "");
        assertEq(rewards, 2_093_000_000_000_000, "with rebalancer trigger");
    }

    /**
     * @custom:scenario Call `getLiquidationRewards` when tx.gasPrice is lower than the oracle's value but both are
     * above the limit
     * @custom:when The tx.gasprice is lower than the oracle gas price feed
     * @custom:and They are both above the gas price limit
     * @custom:and 1 tick was liquidated
     * @custom:and The exchange rate for stETH per wstETH is 1.15
     * @custom:then It should return an amount of wstETH calculated with a gas price equal to the limit
     */
    function test_getLiquidationRewardsWithTxGasPriceAndAboveTheLimit() public {
        vm.txGasPrice(1001 gwei);
        mockChainlinkOnChain.setLatestRoundData(1, 2000 gwei, block.timestamp, 1);

        uint256 rewards =
            liquidationRewardsManager.getLiquidationRewards(1, 0, false, false, Types.ProtocolAction.None, "", "");
        assertEq(rewards, 93_150_000_000_000_000, "without rebase");

        rewards = liquidationRewardsManager.getLiquidationRewards(1, 0, true, false, Types.ProtocolAction.None, "", "");
        assertEq(rewards, 116_150_000_000_000_000, "with rebase");

        rewards = liquidationRewardsManager.getLiquidationRewards(1, 0, false, true, Types.ProtocolAction.None, "", "");
        assertEq(rewards, 104_650_000_000_000_000, "with rebalancer trigger");
    }

    /**
     * @custom:scenario Call `getLiquidationRewards` when the oracle's value is lower than tx.gasPrice but both are
     * above the limit
     * @custom:when The oracle gas price feed is lower than tx.gasprice
     * @custom:and They are both above the gas price limit
     * @custom:and 1 tick was liquidated
     * @custom:and The exchange rate for stETH per wstETH is 1.15
     * @custom:then It should return an amount of wstETH calculated with a gas price equal to the limit
     */
    function test_getLiquidationRewardsWithOracleAndAboveTheLimit() public {
        vm.txGasPrice(2000 gwei);
        mockChainlinkOnChain.setLatestRoundData(1, 1001 gwei, block.timestamp, 1);

        uint256 rewards =
            liquidationRewardsManager.getLiquidationRewards(1, 0, false, false, Types.ProtocolAction.None, "", "");
        assertEq(rewards, 93_150_000_000_000_000, "without rebase");

        rewards = liquidationRewardsManager.getLiquidationRewards(1, 0, true, false, Types.ProtocolAction.None, "", "");
        assertEq(rewards, 116_150_000_000_000_000, "with rebase");

        rewards = liquidationRewardsManager.getLiquidationRewards(1, 0, false, true, Types.ProtocolAction.None, "", "");
        assertEq(rewards, 104_650_000_000_000_000, "with rebalancer trigger");
    }

    /**
     * @custom:scenario Call `getLiquidationRewards` when the oracle returns a negative value
     * @custom:when The oracle returns -1
     * @custom:then It should return 0 to avoid relying solely on tx.gasprice
     */
    function test_getLiquidationRewardsWithOracleGasPriceFeedBroken() public {
        mockChainlinkOnChain.toggleRevert();

        uint256 rewards =
            liquidationRewardsManager.getLiquidationRewards(1, 0, false, false, Types.ProtocolAction.None, "", "");
        assertEq(rewards, 0, "The function should return 0");

        rewards = liquidationRewardsManager.getLiquidationRewards(1, 0, true, false, Types.ProtocolAction.None, "", "");
        assertEq(rewards, 0, "with rebase");

        rewards = liquidationRewardsManager.getLiquidationRewards(1, 0, false, true, Types.ProtocolAction.None, "", "");
        assertEq(rewards, 0, "with rebalancer trigger");
    }

    /**
     * @custom:scenario Call `getLiquidationRewards` return 0 if chainlink data is too old
     * @custom:when The oracle returns data with a timestamp farther than our tolerated time.
     * @custom:then It should return 0 to avoid relying solely on tx.gasprice or old data
     */
    function test_getLiquidationRewardsWithOracleGasPriceTooOld() public {
        mockChainlinkOnChain.setLastPublishTime(0);

        uint256 rewards =
            liquidationRewardsManager.getLiquidationRewards(1, 0, false, false, Types.ProtocolAction.None, "", "");
        assertEq(rewards, 0, "The function should return 0");

        rewards = liquidationRewardsManager.getLiquidationRewards(1, 0, true, false, Types.ProtocolAction.None, "", "");
        assertEq(rewards, 0, "with rebase");

        rewards = liquidationRewardsManager.getLiquidationRewards(1, 0, false, true, Types.ProtocolAction.None, "", "");
        assertEq(rewards, 0, "with rebalancer trigger");
    }
}

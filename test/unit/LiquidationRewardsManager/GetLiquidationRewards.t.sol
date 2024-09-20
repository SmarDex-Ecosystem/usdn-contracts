// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { LiquidationRewardsManagerBaseFixture } from "./utils/Fixtures.sol";

import { IUsdnProtocolTypes as Types } from "../../../src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";

/**
 * @custom:feature The `getLiquidationRewards` function of `LiquidationRewardsManager`
 */
contract TestLiquidationRewardsManagerGetLiquidationRewards is LiquidationRewardsManagerBaseFixture {
    uint256 internal constant CURRENT_PRICE = 1000 ether;

    Types.LiqTickInfo[] internal _singleLiquidatedTick;
    Types.LiqTickInfo[] internal _liquidatedTicksEmpty;

    function setUp() public override {
        super.setUp();

        // Change The rewards calculations parameters to not be dependent of the initial values
        liquidationRewardsManager.setRewardsParameters(
            10_000, 30_000, 20_000, 10_000, 10 gwei, 15_000, 500, 0.1 ether, 1 ether
        );

        // Puts the base fee at 30 gwei
        vm.fee(30 gwei);
        // TX fee is same as base fee + offset
        vm.txGasPrice(40 gwei);

        _singleLiquidatedTick.push(
            Types.LiqTickInfo({
                totalPositions: 1,
                totalExpo: 10 ether,
                remainingCollateral: 0.2 ether,
                tickPrice: 1020 ether,
                priceWithoutPenalty: 1000 ether
            })
        );
    }

    /**
     * @custom:scenario Call `getLiquidationRewards` when 1 tick was liquidated
     * @custom:given The tx.gasprice is equal to the base fee + offset
     * @custom:and The exchange rate for stETH per wstETH is 1.15
     * @custom:and The current price of wstETH is $1000
     * @custom:when 1 tick was liquidated
     * @custom:then It should return an amount of wstETH based on the gas used by
     * UsdnProtocolActions.liquidate(bytes,uint16)
     */
    function test_getLiquidationRewardsFor1Tick() public view {
        uint256 posBonus = (_singleLiquidatedTick[0].tickPrice - CURRENT_PRICE) * _singleLiquidatedTick[0].totalExpo
            * 500 / (BPS_DIVISOR * CURRENT_PRICE);

        uint256 rewards = liquidationRewardsManager.getLiquidationRewards(
            _singleLiquidatedTick, CURRENT_PRICE, false, Types.RebalancerAction.None, Types.ProtocolAction.None, "", ""
        );
        assertEq(
            rewards,
            wsteth.getWstETHByStETH((40 gwei * (21_000 + 30_000 + 10_000) * 15 / 10) + posBonus + 0.1 ether),
            "without rebase"
        );
        rewards = liquidationRewardsManager.getLiquidationRewards(
            _singleLiquidatedTick, CURRENT_PRICE, true, Types.RebalancerAction.None, Types.ProtocolAction.None, "", ""
        );
        assertEq(
            rewards,
            wsteth.getWstETHByStETH((40 gwei * (21_000 + 30_000 + 10_000 + 20_000) * 15 / 10) + posBonus + 0.1 ether),
            "with rebase"
        );
        rewards = liquidationRewardsManager.getLiquidationRewards(
            _singleLiquidatedTick,
            CURRENT_PRICE,
            false,
            Types.RebalancerAction.ClosedOpened,
            Types.ProtocolAction.None,
            "",
            ""
        );
        assertEq(
            rewards,
            wsteth.getWstETHByStETH((40 gwei * (21_000 + 30_000 + 10_000 + 10_000) * 15 / 10) + posBonus + 0.1 ether),
            "with rebalancer trigger"
        );
    }

    /**
     * @custom:scenario Call `getLiquidationRewards` when 0 ticks were liquidated
     * @custom:when No ticks were liquidated
     * @custom:then It should return 0 as we only give rewards on successful liquidations
     */
    function test_getLiquidationRewardsFor0Tick() public view {
        uint256 rewards = liquidationRewardsManager.getLiquidationRewards(
            _liquidatedTicksEmpty, CURRENT_PRICE, false, Types.RebalancerAction.None, Types.ProtocolAction.None, "", ""
        );
        assertEq(rewards, 0, "without rebase");
        rewards = liquidationRewardsManager.getLiquidationRewards(
            _liquidatedTicksEmpty, CURRENT_PRICE, true, Types.RebalancerAction.None, Types.ProtocolAction.None, "", ""
        );
        assertEq(rewards, 0, "with rebase");
        rewards = liquidationRewardsManager.getLiquidationRewards(
            _liquidatedTicksEmpty,
            CURRENT_PRICE,
            false,
            Types.RebalancerAction.ClosedOpened,
            Types.ProtocolAction.None,
            "",
            ""
        );
        assertEq(rewards, 0, "with rebalancer trigger");
    }

    /**
     * @custom:scenario Call `getLiquidationRewards` when 3 ticks were liquidated
     * @custom:given The tx.gasprice is equal to the base fee + offset
     * @custom:and The exchange rate for stETH per wstETH is 1.15
     * @custom:and The current price of wstETH is $1000
     * @custom:when 3 ticks were liquidated
     * @custom:then It should return more wstETH than for 1 tick as more gas was used by
     * UsdnProtocolActions.liquidate(bytes,uint16)
     */
    function test_getLiquidationRewardsFor3Ticks() public view {
        Types.LiqTickInfo[] memory threeLiquidatedTicks = new Types.LiqTickInfo[](3);
        threeLiquidatedTicks[0] = Types.LiqTickInfo({
            totalPositions: 1,
            totalExpo: 10 ether,
            remainingCollateral: 0.2 ether,
            tickPrice: 1020 ether,
            priceWithoutPenalty: 1000 ether
        });
        threeLiquidatedTicks[1] = Types.LiqTickInfo({
            totalPositions: 1,
            totalExpo: 10 ether,
            remainingCollateral: 0.2 ether,
            tickPrice: 1010 ether,
            priceWithoutPenalty: 990 ether
        });
        threeLiquidatedTicks[2] = Types.LiqTickInfo({
            totalPositions: 1,
            totalExpo: 10 ether,
            remainingCollateral: 0.2 ether,
            tickPrice: 1000 ether,
            priceWithoutPenalty: 980 ether
        });

        uint256 posBonus = (threeLiquidatedTicks[0].tickPrice - CURRENT_PRICE) * threeLiquidatedTicks[0].totalExpo * 500
            / (BPS_DIVISOR * CURRENT_PRICE);
        posBonus += (threeLiquidatedTicks[1].tickPrice - CURRENT_PRICE) * threeLiquidatedTicks[1].totalExpo * 500
            / (BPS_DIVISOR * CURRENT_PRICE);
        posBonus += (threeLiquidatedTicks[2].tickPrice - CURRENT_PRICE) * threeLiquidatedTicks[2].totalExpo * 500
            / (BPS_DIVISOR * CURRENT_PRICE);

        uint256 rewards = liquidationRewardsManager.getLiquidationRewards(
            threeLiquidatedTicks, CURRENT_PRICE, false, Types.RebalancerAction.None, Types.ProtocolAction.None, "", ""
        );
        assertEq(
            rewards,
            wsteth.getWstETHByStETH((40 gwei * (21_000 + 30_000 + 3 * 10_000) * 15 / 10) + posBonus + 0.1 ether),
            "The wrong amount of rewards was given"
        );
        assertGt(
            rewards,
            liquidationRewardsManager.getLiquidationRewards(
                _singleLiquidatedTick,
                CURRENT_PRICE,
                false,
                Types.RebalancerAction.None,
                Types.ProtocolAction.None,
                "",
                ""
            ),
            "More rewards should be given if more ticks are liquidated"
        );

        rewards = liquidationRewardsManager.getLiquidationRewards(
            threeLiquidatedTicks, CURRENT_PRICE, true, Types.RebalancerAction.None, Types.ProtocolAction.None, "", ""
        );
        assertEq(
            rewards,
            wsteth.getWstETHByStETH(
                (40 gwei * (21_000 + 30_000 + 3 * 10_000 + 20_000) * 15 / 10) + posBonus + 0.1 ether
            ),
            "with rebase - expected rewards"
        );
        assertGt(
            rewards,
            liquidationRewardsManager.getLiquidationRewards(
                _singleLiquidatedTick,
                CURRENT_PRICE,
                true,
                Types.RebalancerAction.None,
                Types.ProtocolAction.None,
                "",
                ""
            ),
            "with rebase - greater than fewer ticks"
        );
        rewards = liquidationRewardsManager.getLiquidationRewards(
            threeLiquidatedTicks,
            CURRENT_PRICE,
            false,
            Types.RebalancerAction.ClosedOpened,
            Types.ProtocolAction.None,
            "",
            ""
        );
        assertEq(
            rewards,
            wsteth.getWstETHByStETH(
                (40 gwei * (21_000 + 30_000 + 3 * 10_000 + 10_000) * 15 / 10) + posBonus + 0.1 ether
            ),
            "with rebalancer trigger - expected rewards"
        );
        assertGt(
            rewards,
            liquidationRewardsManager.getLiquidationRewards(
                _singleLiquidatedTick,
                CURRENT_PRICE,
                false,
                Types.RebalancerAction.ClosedOpened,
                Types.ProtocolAction.None,
                "",
                ""
            ),
            "with rebalancer trigger - greater than fewer ticks"
        );
    }

    /**
     * @custom:scenario Call `getLiquidationRewards` when the user's priority fee is higher than the base fee offset
     * @custom:given The user's priority fee is higher than the base fee offset
     * @custom:and The exchange rate for stETH per wstETH is 1.15
     * @custom:when 1 tick was liquidated
     * @custom:then It should return an amount of wstETH based on the gas used by
     * UsdnProtocolActions.liquidate(bytes,uint16) and the base fee offset
     */
    function test_getLiquidationRewardsUserPriorityFee() public {
        vm.txGasPrice(41 gwei); // 11 gwei priority fee
        uint256 posBonus = (_singleLiquidatedTick[0].tickPrice - CURRENT_PRICE) * _singleLiquidatedTick[0].totalExpo
            * 500 / (BPS_DIVISOR * CURRENT_PRICE);

        uint256 rewards = liquidationRewardsManager.getLiquidationRewards(
            _singleLiquidatedTick, CURRENT_PRICE, false, Types.RebalancerAction.None, Types.ProtocolAction.None, "", ""
        );
        assertEq(
            rewards,
            wsteth.getWstETHByStETH((40 gwei * (21_000 + 30_000 + 10_000) * 15 / 10) + posBonus + 0.1 ether),
            "without rebase"
        );

        rewards = liquidationRewardsManager.getLiquidationRewards(
            _singleLiquidatedTick, CURRENT_PRICE, true, Types.RebalancerAction.None, Types.ProtocolAction.None, "", ""
        );
        assertEq(
            rewards,
            wsteth.getWstETHByStETH((40 gwei * (21_000 + 30_000 + 10_000 + 20_000) * 15 / 10) + posBonus + 0.1 ether),
            "with rebase"
        );

        rewards = liquidationRewardsManager.getLiquidationRewards(
            _singleLiquidatedTick,
            CURRENT_PRICE,
            false,
            Types.RebalancerAction.ClosedOpened,
            Types.ProtocolAction.None,
            "",
            ""
        );
        assertEq(
            rewards,
            wsteth.getWstETHByStETH((40 gwei * (21_000 + 30_000 + 10_000 + 10_000) * 15 / 10) + posBonus + 0.1 ether),
            "with rebalancer trigger"
        );
    }

    /**
     * @custom:scenario Call `getLiquidationRewards` when the user's priority fee is lower than the base fee offset
     * @custom:given The user's priority fee is lower than the base fee offset
     * @custom:and The exchange rate for stETH per wstETH is 1.15
     * @custom:when 1 tick was liquidated
     * @custom:then It should return an amount of wstETH based on the gas used by
     * UsdnProtocolActions.liquidate(bytes,uint16) and the base fee offset
     */
    function test_getLiquidationRewardsWithTxGasPrice() public {
        vm.txGasPrice(31 gwei); // priority fee 1 gwei
        uint256 posBonus = (_singleLiquidatedTick[0].tickPrice - CURRENT_PRICE) * _singleLiquidatedTick[0].totalExpo
            * 500 / (BPS_DIVISOR * CURRENT_PRICE);

        uint256 rewards = liquidationRewardsManager.getLiquidationRewards(
            _singleLiquidatedTick, CURRENT_PRICE, false, Types.RebalancerAction.None, Types.ProtocolAction.None, "", ""
        );
        assertEq(
            rewards,
            wsteth.getWstETHByStETH((31 gwei * (21_000 + 30_000 + 10_000) * 15 / 10) + posBonus + 0.1 ether),
            "without rebase"
        );

        rewards = liquidationRewardsManager.getLiquidationRewards(
            _singleLiquidatedTick, CURRENT_PRICE, true, Types.RebalancerAction.None, Types.ProtocolAction.None, "", ""
        );
        assertEq(
            rewards,
            wsteth.getWstETHByStETH((31 gwei * (21_000 + 30_000 + 10_000 + 20_000) * 15 / 10) + posBonus + 0.1 ether),
            "with rebase"
        );

        rewards = liquidationRewardsManager.getLiquidationRewards(
            _singleLiquidatedTick,
            CURRENT_PRICE,
            false,
            Types.RebalancerAction.ClosedOpened,
            Types.ProtocolAction.None,
            "",
            ""
        );
        assertEq(
            rewards,
            wsteth.getWstETHByStETH((31 gwei * (21_000 + 30_000 + 10_000 + 10_000) * 15 / 10) + posBonus + 0.1 ether),
            "with rebalancer trigger"
        );
    }

    /**
     * @custom:scenario Call `getLiquidationRewards` when the reward amount is greater than the `maxReward`
     * @custom:given The max reward is set to 0.1 wstETH
     * @custom:and The parameters for the reward would result in a reward greater than the max reward
     * @custom:when The liquidation reward is calculated
     * @custom:then It should return the max reward in wstETH
     */
    function test_getLiquidationRewardsWithLimit() public {
        liquidationRewardsManager.setRewardsParameters(0, 0, 0, 0, 0, 0, 0, 0.5 ether, 0.1 ether);
        uint256 rewards = liquidationRewardsManager.getLiquidationRewards(
            _singleLiquidatedTick, CURRENT_PRICE, false, Types.RebalancerAction.None, Types.ProtocolAction.None, "", ""
        );
        assertEq(rewards, wsteth.getWstETHByStETH(0.1 ether), "reward");
    }
}

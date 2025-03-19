// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { BaseFixture } from "../../utils/Fixtures.sol";

import { LiquidationRewardsManagerWusdn } from
    "../../../src/LiquidationRewardsManager/LiquidationRewardsManagerWusdn.sol";
import { Usdn } from "../../../src/Usdn/Usdn.sol";
import { Wusdn } from "../../../src/Usdn/Wusdn.sol";
import { ILiquidationRewardsManagerErrorsEventsTypes } from
    "../../../src/interfaces/LiquidationRewardsManager/ILiquidationRewardsManagerErrorsEventsTypes.sol";
import { IWusdn } from "../../../src/interfaces/Usdn/IWusdn.sol";
import { IUsdnProtocolTypes as Types } from "../../../src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";

/// @custom:feature The `getLiquidationRewards` function of `LiquidationRewardsManagerWusdn`
contract TestLiquidationRewardsManagerWusdnGetLiquidationRewards is BaseFixture {
    IWusdn internal wusdn;
    LiquidationRewardsManagerWusdn internal liquidationRewardsManager;
    ILiquidationRewardsManagerErrorsEventsTypes.RewardsParameters rewardsParameters;

    uint256 internal constant CURRENT_PRICE = 1 ether / 1000; // 0.001 eth/wUsdn

    Types.LiqTickInfo[] internal _singleLiquidatedTick;
    Types.LiqTickInfo[] internal _liquidatedTicksEmpty;

    function setUp() public {
        wusdn = new Wusdn(new Usdn(address(0), address(0)));
        liquidationRewardsManager = new LiquidationRewardsManagerWusdn(wusdn);

        liquidationRewardsManager.setRewardsParameters(
            50_000, 500_000, 0, 300_000, 2 gwei, 10_500, 200, 2 ether, 1000 ether
        );

        rewardsParameters = liquidationRewardsManager.getRewardsParameters();

        vm.fee(30 gwei);
        vm.txGasPrice(40 gwei);

        _singleLiquidatedTick.push(
            Types.LiqTickInfo({
                totalPositions: 1,
                totalExpo: 10_000 ether,
                remainingCollateral: -200 ether,
                tickPrice: 1.02 ether / 1000, // 0.00102 eth/wUsdn
                priceWithoutPenalty: 1 ether / 1000 // 0.001 eth/wUsdn
             })
        );
    }

    /**
     * @custom:scenario Call `getLiquidationRewards` when 1 tick was liquidated
     * @custom:given The tx.gasprice is equal to the base fee + offset
     * @custom:and The current price of is 0.001 eth/wUsdn
     * @custom:when 1 tick was liquidated
     * @custom:then It should return an amount of wUsdn based on the gas used by UsdnProtocolActions.liquidate(bytes)
     */
    function test_getLiquidationRewardsFor1Tick() public view {
        uint256 posBonusWusdn = (
            _singleLiquidatedTick[0].totalExpo * (_singleLiquidatedTick[0].tickPrice - CURRENT_PRICE) / CURRENT_PRICE
        ) * 200 / BPS_DIVISOR;

        uint256 gasPriceAndMultiplier =
            (rewardsParameters.baseFeeOffset + block.basefee) * rewardsParameters.gasMultiplierBps / BPS_DIVISOR;

        uint256 gasUsed = rewardsParameters.otherGasUsed + liquidationRewardsManager.BASE_GAS_COST()
            + uint256(rewardsParameters.gasUsedPerTick) * _singleLiquidatedTick.length;
        uint256 totRewards =
            rewardsParameters.fixedReward + posBonusWusdn + gasUsed * gasPriceAndMultiplier * 1e18 / CURRENT_PRICE;
        uint256 rewards = liquidationRewardsManager.getLiquidationRewards(
            _singleLiquidatedTick, CURRENT_PRICE, false, Types.RebalancerAction.None, Types.ProtocolAction.None, "", ""
        );
        assertEq(rewards, totRewards, "without rebalancer trigger");

        gasUsed += rewardsParameters.rebalancerGasUsed;
        totRewards =
            rewardsParameters.fixedReward + posBonusWusdn + gasUsed * gasPriceAndMultiplier * 1e18 / CURRENT_PRICE;
        rewards = liquidationRewardsManager.getLiquidationRewards(
            _singleLiquidatedTick,
            CURRENT_PRICE,
            true,
            Types.RebalancerAction.ClosedOpened,
            Types.ProtocolAction.None,
            "",
            ""
        );
        assertEq(rewards, totRewards, "with rebalancer trigger");
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
}

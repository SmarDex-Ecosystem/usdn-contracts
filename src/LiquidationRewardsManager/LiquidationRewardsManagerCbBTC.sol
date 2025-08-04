// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

import { IWstETH } from "../interfaces/IWstETH.sol";
import { IBaseLiquidationRewardsManager } from
    "../interfaces/LiquidationRewardsManager/IBaseLiquidationRewardsManager.sol";
import { IUsdnProtocolTypes as Types } from "../interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import { LiquidationRewardsManager } from "./LiquidationRewardsManager.sol";

/**
 * @title Liquidation Rewards Manager for Wrapped stETH
 * @notice This contract calculates rewards for liquidators within the USDN protocol, using wstETH as the underlying
 * asset. Rewards are computed based on gas costs, which are converted to wstETH using the current conversion rate
 * between wstETH and stETH, assuming a one-to-one rate between stETH and ETH. Additionally a fixed reward is added
 * along with a bonus based on the size of the liquidated ticks.
 */
contract LiquidationRewardsManagerWstEth is LiquidationRewardsManager {
    /// @param wstETH The address of the wstETH token.
    constructor(IWstETH wstETH) Ownable(msg.sender) {
        _rewardAsset = wstETH;
        _rewardsParameters = RewardsParameters({
            gasUsedPerTick: 53_094,
            otherGasUsed: 469_537,
            rebaseGasUsed: 13_765,
            rebalancerGasUsed: 279_349,
            baseFeeOffset: 2 gwei,
            gasMultiplierBps: 10_500, // 1.05
            positionBonusMultiplierBps: 200, // 0.02
            fixedReward: 0.00001 ether,
            maxReward: 0.001 ether
        });
    }

    /// @inheritdoc IBaseLiquidationRewardsManager
    function getLiquidationRewards(
        Types.LiqTickInfo[] calldata liquidatedTicks,
        uint256 currentPrice,
        bool rebased,
        Types.RebalancerAction rebalancerAction,
        Types.ProtocolAction,
        bytes calldata,
        bytes calldata
    ) external view override returns (uint256 cbBtcRewards_) {
        if (liquidatedTicks.length == 0) {
            return 0;
        }

        RewardsParameters memory rewardsParameters = _rewardsParameters;
        // calculate the amount of gas spent during the liquidation
        uint256 gasUsed = rewardsParameters.otherGasUsed + BASE_GAS_COST
            + uint256(rewardsParameters.gasUsedPerTick) * liquidatedTicks.length;
        if (rebased) {
            gasUsed += rewardsParameters.rebaseGasUsed;
        }
        if (uint8(rebalancerAction) > uint8(Types.RebalancerAction.NoCloseNoOpen)) {
            gasUsed += rewardsParameters.rebalancerGasUsed;
        }

        uint256 totalRewardETH = rewardsParameters.fixedReward
            + _calcGasPrice(rewardsParameters.baseFeeOffset) * gasUsed * rewardsParameters.gasMultiplierBps / BPS_DIVISOR;

        uint256 wstEthBonus =
            _calcPositionSizeBonus(liquidatedTicks, currentPrice, rewardsParameters.positionBonusMultiplierBps);

        totalRewardETH += IWstETH(address(_rewardAsset)).getStETHByWstETH(wstEthBonus);

        if (totalRewardETH > rewardsParameters.maxReward) {
            totalRewardETH = rewardsParameters.maxReward;
        }

        // convert to wstETH
        cbBtcRewards_ = IWstETH(address(_rewardAsset)).getWstETHByStETH(totalRewardETH);
    }
}

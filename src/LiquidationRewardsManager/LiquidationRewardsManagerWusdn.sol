// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { FixedPointMathLib } from "solady/src/utils/FixedPointMathLib.sol";

import { IBaseLiquidationRewardsManager } from
    "../interfaces/LiquidationRewardsManager/IBaseLiquidationRewardsManager.sol";
import { IWusdn } from "../interfaces/Usdn/IWusdn.sol";
import { IUsdnProtocolTypes as Types } from "../interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import { LiquidationRewardsManager } from "./LiquidationRewardsManager.sol";

/**
 * @title Liquidation Rewards Manager for Wrapped USDN
 * @notice This contract calculates rewards for liquidators within the USDN protocol with wUsdn as underlying asset.
 * @dev Rewards are computed based on gas costs, position size, and other parameters.
 */
contract LiquidationRewardsManagerWusdn is LiquidationRewardsManager {
    /// @notice The precision used for the price.
    uint256 public constant PRICE_DECIMALS = 1e18;

    /// @param wusdn The address of the wUsdn token.
    constructor(IWusdn wusdn) Ownable(msg.sender) {
        _rewardAsset = wusdn;
        _rewardsParameters = RewardsParameters({
            gasUsedPerTick: 53_094,
            otherGasUsed: 469_537,
            rebaseGasUsed: 13_765,
            rebalancerGasUsed: 279_349,
            baseFeeOffset: 2 gwei,
            gasMultiplierBps: 10_500, // 1.05
            positionBonusMultiplierBps: 200, // 0.02
            fixedReward: 2 ether,
            maxReward: 1000 ether
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
    ) external view override returns (uint256 wUsdnRewards_) {
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

        uint256 gasRewards =
            _calcGasPrice(rewardsParameters.baseFeeOffset) * gasUsed * rewardsParameters.gasMultiplierBps / BPS_DIVISOR;

        wUsdnRewards_ = rewardsParameters.fixedReward
            + _calcPositionSizeBonus(liquidatedTicks, currentPrice, rewardsParameters.positionBonusMultiplierBps);

        wUsdnRewards_ += FixedPointMathLib.fullMulDiv(gasRewards, PRICE_DECIMALS, currentPrice);

        if (wUsdnRewards_ > rewardsParameters.maxReward) {
            wUsdnRewards_ = rewardsParameters.maxReward;
        }
    }
}

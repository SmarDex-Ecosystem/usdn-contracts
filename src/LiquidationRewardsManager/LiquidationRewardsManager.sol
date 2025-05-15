// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import { Ownable2Step } from "@openzeppelin/contracts/access/Ownable2Step.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { FixedPointMathLib } from "solady/src/utils/FixedPointMathLib.sol";

import { IBaseLiquidationRewardsManager } from
    "../interfaces/LiquidationRewardsManager/IBaseLiquidationRewardsManager.sol";
import { ILiquidationRewardsManager } from "../interfaces/LiquidationRewardsManager/ILiquidationRewardsManager.sol";
import { IUsdnProtocolTypes as Types } from "../interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";

/**
 * @title Liquidation Rewards Manager
 * @dev This abstract contract calculates the bonus portion of the rewards based on the size of the liquidated ticks.
 * The actual reward calculation is left to the implementing contract.
 */
abstract contract LiquidationRewardsManager is ILiquidationRewardsManager, Ownable2Step {
    /* -------------------------------------------------------------------------- */
    /*                                  Constants                                 */
    /* -------------------------------------------------------------------------- */

    /// @inheritdoc ILiquidationRewardsManager
    uint32 public constant BPS_DIVISOR = 10_000;

    /// @inheritdoc ILiquidationRewardsManager
    uint256 public constant BASE_GAS_COST = 21_000;

    /// @inheritdoc ILiquidationRewardsManager
    uint256 public constant MAX_GAS_USED_PER_TICK = 500_000;

    /// @inheritdoc ILiquidationRewardsManager
    uint256 public constant MAX_OTHER_GAS_USED = 1_000_000;

    /// @inheritdoc ILiquidationRewardsManager
    uint256 public constant MAX_REBASE_GAS_USED = 200_000;

    /// @inheritdoc ILiquidationRewardsManager
    uint256 public constant MAX_REBALANCER_GAS_USED = 300_000;

    /* -------------------------------------------------------------------------- */
    /*                              Storage Variables                             */
    /* -------------------------------------------------------------------------- */

    /// @notice The address of the reward asset.
    IERC20 internal immutable _rewardAsset;

    /**
     * @notice Holds the parameters used for rewards calculation.
     * @dev Parameters should be updated to reflect changes in gas costs or protocol adjustments.
     */
    RewardsParameters internal _rewardsParameters;

    /// @inheritdoc IBaseLiquidationRewardsManager
    function getLiquidationRewards(
        Types.LiqTickInfo[] calldata liquidatedTicks,
        uint256 currentPrice,
        bool rebased,
        Types.RebalancerAction rebalancerAction,
        Types.ProtocolAction action,
        bytes calldata rebaseCallbackResult,
        bytes calldata priceData
    ) external view virtual returns (uint256 rewards_);

    /// @inheritdoc ILiquidationRewardsManager
    function getRewardsParameters() external view returns (RewardsParameters memory) {
        return _rewardsParameters;
    }

    /// @inheritdoc ILiquidationRewardsManager
    function setRewardsParameters(
        uint32 gasUsedPerTick,
        uint32 otherGasUsed,
        uint32 rebaseGasUsed,
        uint32 rebalancerGasUsed,
        uint64 baseFeeOffset,
        uint16 gasMultiplierBps,
        uint16 positionBonusMultiplierBps,
        uint128 fixedReward,
        uint128 maxReward
    ) external onlyOwner {
        if (gasUsedPerTick > MAX_GAS_USED_PER_TICK) {
            revert LiquidationRewardsManagerGasUsedPerTickTooHigh(gasUsedPerTick);
        } else if (otherGasUsed > MAX_OTHER_GAS_USED) {
            revert LiquidationRewardsManagerOtherGasUsedTooHigh(otherGasUsed);
        } else if (rebaseGasUsed > MAX_REBASE_GAS_USED) {
            revert LiquidationRewardsManagerRebaseGasUsedTooHigh(rebaseGasUsed);
        } else if (rebalancerGasUsed > MAX_REBALANCER_GAS_USED) {
            revert LiquidationRewardsManagerRebalancerGasUsedTooHigh(rebalancerGasUsed);
        }

        _rewardsParameters = RewardsParameters({
            gasUsedPerTick: gasUsedPerTick,
            otherGasUsed: otherGasUsed,
            rebaseGasUsed: rebaseGasUsed,
            rebalancerGasUsed: rebalancerGasUsed,
            baseFeeOffset: baseFeeOffset,
            gasMultiplierBps: gasMultiplierBps,
            positionBonusMultiplierBps: positionBonusMultiplierBps,
            fixedReward: fixedReward,
            maxReward: maxReward
        });

        emit RewardsParametersUpdated(
            gasUsedPerTick,
            otherGasUsed,
            rebaseGasUsed,
            rebalancerGasUsed,
            baseFeeOffset,
            gasMultiplierBps,
            positionBonusMultiplierBps,
            fixedReward,
            maxReward
        );
    }

    /**
     * @notice Calculates the gas price used for rewards calculations.
     * @param baseFeeOffset An offset added to the block's base gas fee.
     * @return gasPrice_ The gas price used for reward calculation.
     */
    function _calcGasPrice(uint64 baseFeeOffset) internal view returns (uint256 gasPrice_) {
        gasPrice_ = block.basefee + baseFeeOffset;
        if (gasPrice_ > tx.gasprice) {
            gasPrice_ = tx.gasprice;
        }
    }

    /**
     * @notice Computes the size and price-dependent bonus given for liquidating the ticks.
     * @param liquidatedTicks Information about the liquidated ticks.
     * @param currentPrice The current asset price.
     * @param multiplier The bonus multiplier (in BPS).
     * @return bonus_ The calculated bonus (in _rewardAsset).
     */
    function _calcPositionSizeBonus(
        Types.LiqTickInfo[] calldata liquidatedTicks,
        uint256 currentPrice,
        uint16 multiplier
    ) internal pure returns (uint256 bonus_) {
        uint256 length = liquidatedTicks.length;
        uint256 i;
        do {
            if (currentPrice >= liquidatedTicks[i].tickPrice) {
                // the currentPrice should never exceed the tick price, as a tick cannot be liquidated when the current
                // price is greater than the tick price
                // if this condition occurs, the bonus is clamped to 0
                // additionally, when the `currentPrice` equals the tick price, the bonus is 0 by definition of the
                // formula, so the calculation can be skipped
                unchecked {
                    i++;
                }
                continue;
            }
            uint256 priceDiff;
            unchecked {
                priceDiff = liquidatedTicks[i].tickPrice - currentPrice;
            }
            bonus_ += FixedPointMathLib.fullMulDiv(liquidatedTicks[i].totalExpo, priceDiff, currentPrice);
            unchecked {
                i++;
            }
        } while (i < length);
        bonus_ = bonus_ * multiplier / BPS_DIVISOR;
    }
}

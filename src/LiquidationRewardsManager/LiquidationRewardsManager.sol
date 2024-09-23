// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Ownable2Step } from "@openzeppelin/contracts/access/Ownable2Step.sol";
import { FixedPointMathLib } from "solady/src/utils/FixedPointMathLib.sol";

import { IWstETH } from "../interfaces/IWstETH.sol";
import { IBaseLiquidationRewardsManager } from
    "../interfaces/LiquidationRewardsManager/IBaseLiquidationRewardsManager.sol";
import { ILiquidationRewardsManager } from "../interfaces/LiquidationRewardsManager/ILiquidationRewardsManager.sol";
import { IUsdnProtocolTypes as Types } from "../interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";

/**
 * @title LiquidationRewardsManager contract
 * @notice This contract is used by the USDN protocol to calculate the rewards that need to be paid out to the
 * liquidators
 */
contract LiquidationRewardsManager is ILiquidationRewardsManager, Ownable2Step {
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

    /// @notice Address of the wstETH contract
    IWstETH private immutable _wstEth;

    /**
     * @notice Parameters for the rewards calculation
     * @dev Those values need to be updated if the gas cost changes
     */
    RewardsParameters private _rewardsParameters;

    /// @param wstETH The address of the wstETH token
    constructor(IWstETH wstETH) Ownable(msg.sender) {
        _wstEth = wstETH;
        _rewardsParameters = RewardsParameters({
            gasUsedPerTick: 54_165,
            otherGasUsed: 384_584,
            rebaseGasUsed: 7709,
            rebalancerGasUsed: 257_099,
            baseFeeOffset: 2 gwei,
            gasMultiplierBps: 10_500, // 1.05
            positionBonusMultiplierBps: 200, // 0.02
            fixedReward: 0.001 ether,
            maxReward: 0.5 ether
        });
    }

    /**
     * @inheritdoc IBaseLiquidationRewardsManager
     * @dev In the current implementation, the `ProtocolAction action`, `bytes calldata rebaseCallbackResult` and
     * `bytes calldata priceData` parameters are not used
     */
    function getLiquidationRewards(
        Types.LiqTickInfo[] calldata liquidatedTicks,
        uint256 currentPrice,
        bool rebased,
        Types.RebalancerAction rebalancerAction,
        Types.ProtocolAction,
        bytes calldata,
        bytes calldata
    ) external view returns (uint256 wstETHRewards_) {
        // do not give rewards if no ticks were liquidated
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

        uint256 totalRewardETH =
            _calcGasPrice(rewardsParameters.baseFeeOffset) * gasUsed * rewardsParameters.gasMultiplierBps / BPS_DIVISOR;
        totalRewardETH += rewardsParameters.fixedReward
            + _calcPositionSizeBonus(liquidatedTicks, currentPrice, rewardsParameters.positionBonusMultiplierBps);
        if (totalRewardETH > rewardsParameters.maxReward) {
            totalRewardETH = rewardsParameters.maxReward;
        }
        // convert to wstETH
        wstETHRewards_ = _wstEth.getWstETHByStETH(totalRewardETH);
    }

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
     * @notice Calculate the gas price to use for the liquidation rewards calculation
     * @dev If the tx gas price is lower than the calculated value, then we use the tx gas price
     * @param baseFeeOffset The offset to add to the block's base gas fee
     * @return gasPrice_ The gas price to use for the calculation
     */
    function _calcGasPrice(uint64 baseFeeOffset) internal view returns (uint256 gasPrice_) {
        gasPrice_ = block.basefee + baseFeeOffset;
        if (gasPrice_ > tx.gasprice) {
            gasPrice_ = tx.gasprice;
        }
    }

    /**
     * @notice Calculate the size and price-dependent bonus given for liquidating the ticks
     * @param liquidatedTicks Information about the liquidated ticks
     * @param currentPrice The current price of the asset
     * @param multiplier The bonus multiplier
     * @return bonus_ The bonus for liquidated all the ticks (in native currency, will be converted to wstETH)
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
                // the currentPrice should never exceed the tick price, we can't liquidate a tick when the current
                // price is above its price
                // if that would happen, the bonus is clamped to 0
                // if the price is equal to the tick price, the bonus is also 0 according to the formula so we can
                // skip the calculation
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

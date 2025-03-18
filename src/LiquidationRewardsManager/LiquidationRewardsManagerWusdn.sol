// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Ownable2Step } from "@openzeppelin/contracts/access/Ownable2Step.sol";
import { FixedPointMathLib } from "solady/src/utils/FixedPointMathLib.sol";

import { IBaseLiquidationRewardsManager } from
    "../interfaces/LiquidationRewardsManager/IBaseLiquidationRewardsManager.sol";
import { ILiquidationRewardsManager } from "../interfaces/LiquidationRewardsManager/ILiquidationRewardsManager.sol";
import { IWusdn } from "../interfaces/Usdn/IWusdn.sol";
import { IUsdnProtocolTypes as Types } from "../interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";

/**
 * @title Liquidation Rewards Manager
 * @notice This contract calculates rewards for liquidators within the USDN protocol.
 * @dev Rewards are computed based on gas costs, position size, and other parameters.
 */
contract WusdnLiquidationRewardsManager is ILiquidationRewardsManager, Ownable2Step {
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

    /// @notice The address of the wrapped Usdn (wUsdn) token contract.
    IWusdn private immutable _wusdn;

    /**
     * @notice Holds the parameters used for rewards calculation.
     * @dev Parameters should be updated to reflect changes in gas costs or protocol adjustments.
     */
    RewardsParameters private _rewardsParameters;

    /// @param wUsdn The address of the wUsdn token.
    constructor(IWusdn wUsdn) Ownable(msg.sender) {
        _wusdn = wUsdn;
        _rewardsParameters = RewardsParameters({
            gasUsedPerTick: 53_094,
            otherGasUsed: 469_537,
            rebaseGasUsed: 13_765,
            rebalancerGasUsed: 279_349,
            baseFeeOffset: 2 gwei,
            gasMultiplierBps: 10_500, // 1.05
            positionBonusMultiplierBps: 200, // 0.02
            fixedReward: 0.001 ether,
            maxReward: 0.5 ether
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
    ) external view returns (uint256 wUsdnRewards_) {
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

        wUsdnRewards_ += FixedPointMathLib.fullMulDiv(gasRewards, BPS_DIVISOR, currentPrice);

        if (wUsdnRewards_ > rewardsParameters.maxReward) {
            wUsdnRewards_ = rewardsParameters.maxReward;
        }
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
     * @return bonus_ The calculated bonus (in wstETH).
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

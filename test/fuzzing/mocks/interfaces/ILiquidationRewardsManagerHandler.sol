// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

/**
 * @title Liquidation Rewards Manager Handler Interface
 * @dev Interface for determining reward parameters for liquidation handlers
 */
interface ILiquidationRewardsManagerHandler {
    /**
     * @notice Get reward parameters for liquidation handlers based on a seed value
     * @dev Calculates various gas metrics and reward values based on the provided seed
     * @param seed A random value used to determine reward parameters
     * @return gasUsedPerTick The estimated gas used per tick in liquidation operations
     * @return otherGasUsed Additional gas costs for miscellaneous operations
     * @return rebaseGasUsed Gas used for rebase operations in the liquidation process
     * @return rebalancerGasUsed Gas used by rebalancer functions during liquidation
     * @return baseFeeOffset Base fee adjustment for reward calculations
     * @return gasMultiplierBps Gas multiplier in basis points (1/100 of a percent)
     * @return positionBonusMultiplierBps Position bonus multiplier in basis points
     * @return fixedReward Minimum guaranteed reward amount
     * @return maxReward Maximum possible reward amount
     */
    function getRewardsParameters(uint256 seed)
        external
        pure
        returns (
            uint32 gasUsedPerTick,
            uint32 otherGasUsed,
            uint32 rebaseGasUsed,
            uint32 rebalancerGasUsed,
            uint64 baseFeeOffset,
            uint16 gasMultiplierBps,
            uint16 positionBonusMultiplierBps,
            uint128 fixedReward,
            uint128 maxReward
        );
}

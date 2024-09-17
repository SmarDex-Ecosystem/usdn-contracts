// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

interface ILiquidationRewardsManagerErrorsEventsTypes {
    /* -------------------------------------------------------------------------- */
    /*                                   Events                                   */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice Emitted when the rewards parameters are changed
     * @param gasUsedPerTick Gas used per tick to liquidate
     * @param otherGasUsed Gas used for the rest of the computation
     * @param rebaseGasUsed Gas used for the optional USDN rebase
     * @param rebalancerGasUsed Gas used for the optional rebalancer trigger
     * @param baseFeeOffset Offset added to the block's base gas fee
     * @param gasMultiplierBps Multiplier for the amount of gas used in BPS
     * @param positionBonusMultiplierBps Multiplier for the position size bonus in BPS
     * @param fixedReward fixed amount added to the final reward (native currency)
     * @param maxReward Upper limit for the rewards (native currency)
     */
    event RewardsParametersUpdated(
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

    /* -------------------------------------------------------------------------- */
    /*                                    Structs                                 */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice Parameters for the rewards calculation
     * @param gasUsedPerTick Gas used per tick to liquidate
     * @param otherGasUsed Gas used for the rest of the computation
     * @param rebaseGasUsed Gas used for the optional USDN rebase
     * @param rebalancerGasUsed Gas used for the optional rebalancer trigger
     * @param baseFeeOffset Offset added to the block's base gas fee
     * @param gasMultiplierBps Multiplier for the amount of gas used (max 6.55x)
     * @param positionBonusMultiplierBps Multiplier for the position size bonus (max 6.55x)
     * @param fixedReward fixed amount added to the final reward (native currency)
     * @param maxReward Upper limit for the rewards (native currency)
     */
    struct RewardsParameters {
        uint32 gasUsedPerTick;
        uint32 otherGasUsed;
        uint32 rebaseGasUsed;
        uint32 rebalancerGasUsed;
        uint64 baseFeeOffset;
        uint16 gasMultiplierBps;
        uint16 positionBonusMultiplierBps;
        uint128 fixedReward;
        uint128 maxReward;
    }

    /* -------------------------------------------------------------------------- */
    /*                                   Errors                                   */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice Indicates that the gasUsedPerTick parameter has been set to a value we consider too high
     * @param value The wanted value
     */
    error LiquidationRewardsManagerGasUsedPerTickTooHigh(uint256 value);

    /**
     * @notice Indicates that the otherGasUsed parameter has been set to a value we consider too high
     * @param value The wanted value
     */
    error LiquidationRewardsManagerOtherGasUsedTooHigh(uint256 value);

    /**
     * @notice Indicates that the rebaseGasUsed parameter has been set to a value we consider too high
     * @param value The wanted value
     */
    error LiquidationRewardsManagerRebaseGasUsedTooHigh(uint256 value);

    /**
     * @notice Indicates that the rebalancerGasUsed parameter has been set to a value we consider too high
     * @param value The wanted value
     */
    error LiquidationRewardsManagerRebalancerGasUsedTooHigh(uint256 value);

    /**
     * @notice Indicates that the maxReward parameter has been set to a value considered too low
     * @param value The wanted value
     */
    error LiquidationRewardsManagerMaxRewardTooLow(uint256 value);
}

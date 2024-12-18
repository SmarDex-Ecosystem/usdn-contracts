// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

/// @notice Interface defining events, structs, and errors for the {LiquidationRewardsManager}.
interface ILiquidationRewardsManagerErrorsEventsTypes {
    /* -------------------------------------------------------------------------- */
    /*                                   Events                                   */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice The rewards parameters are updated.
     * @param gasUsedPerTick The gas consumed per tick for liquidation.
     * @param otherGasUsed The gas consumed for all additional computations.
     * @param rebaseGasUsed The gas consumed for optional USDN rebase operation.
     * @param rebalancerGasUsed The gas consumed for the optional rebalancer trigger.
     * @param baseFeeOffset An offset added to the block's base gas fee.
     * @param gasMultiplierBps Multiplier for the gas usage (in BPS).
     * @param positionBonusMultiplierBps Multiplier for position size bonus (in BPS).
     * @param fixedReward A fixed reward amount (in native currency, converted to wstETH).
     * @param maxReward The maximum allowable reward amount (in native currency, converted to wstETH).
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
     * @notice The parameters used for calculating rewards.
     * @param gasUsedPerTick The gas consumed per tick for liquidation.
     * @param otherGasUsed The gas consumed for all additional computations.
     * @param rebaseGasUsed The gas consumed for optional USDN rebase operation.
     * @param rebalancerGasUsed The gas consumed for the optional rebalancer trigger.
     * @param baseFeeOffset An offset added to the block's base gas fee.
     * @param gasMultiplierBps Multiplier for the gas usage (in BPS).
     * @param positionBonusMultiplierBps Multiplier for position size bonus (in BPS).
     * @param fixedReward A fixed reward amount (in native currency, converted to wstETH).
     * @param maxReward The maximum allowable reward amount (in native currency, converted to wstETH).
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
     * @notice The `gasUsedPerTick` parameter exceeds the allowable limit.
     * @param value The given value.
     */
    error LiquidationRewardsManagerGasUsedPerTickTooHigh(uint256 value);

    /**
     * @notice The `otherGasUsed` parameter exceeds the allowable limit.
     * @param value The given value.
     */
    error LiquidationRewardsManagerOtherGasUsedTooHigh(uint256 value);

    /**
     * @notice The `rebaseGasUsed` parameter exceeds the allowable limit.
     * @param value The given value.
     */
    error LiquidationRewardsManagerRebaseGasUsedTooHigh(uint256 value);

    /**
     * @notice The `rebalancerGasUsed` parameter exceeds the allowable limit.
     * @param value The given value.
     */
    error LiquidationRewardsManagerRebalancerGasUsedTooHigh(uint256 value);

    /**
     * @notice The `maxReward` parameter is below the allowable minimum.
     * @param value The given value.
     */
    error LiquidationRewardsManagerMaxRewardTooLow(uint256 value);
}

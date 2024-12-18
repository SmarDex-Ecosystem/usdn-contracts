// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import { IBaseLiquidationRewardsManager } from "./IBaseLiquidationRewardsManager.sol";
import { ILiquidationRewardsManagerErrorsEventsTypes } from "./ILiquidationRewardsManagerErrorsEventsTypes.sol";

/// @notice Interface for managing liquidation rewards within the protocol.
interface ILiquidationRewardsManager is IBaseLiquidationRewardsManager, ILiquidationRewardsManagerErrorsEventsTypes {
    /**
     * @notice Gets the denominator used for the reward multipliers.
     * @return The BPS divisor.
     */
    function BPS_DIVISOR() external pure returns (uint32);

    /**
     * @notice Gets the fixed gas amount used as a base for transaction cost computations.
     * @dev Stored as a uint256 to prevent overflow during gas usage computations.
     * @return The base gas cost.
     */
    function BASE_GAS_COST() external pure returns (uint256);

    /**
     * @notice Gets the maximum allowable gas usage per liquidated tick.
     * @return The maximum gas used per tick.
     */
    function MAX_GAS_USED_PER_TICK() external pure returns (uint256);

    /**
     * @notice Gets the maximum allowable gas usage for all other computations.
     * @return The maximum gas used for additional computations.
     */
    function MAX_OTHER_GAS_USED() external pure returns (uint256);

    /**
     * @notice Gets the maximum allowable gas usage for rebase operations.
     * @return The maximum gas used for rebase operations.
     */
    function MAX_REBASE_GAS_USED() external pure returns (uint256);

    /**
     * @notice Gets the maximum allowable gas usage for triggering the optional rebalancer.
     * @return The maximum gas used for the optional rebalancer trigger.
     */
    function MAX_REBALANCER_GAS_USED() external pure returns (uint256);

    /**
     * @notice Retrieves the current parameters used for reward calculations.
     * @return rewardsParameters_ A struct containing the rewards parameters.
     */
    function getRewardsParameters() external view returns (RewardsParameters memory);

    /**
     * @notice Updates the parameters used for calculating liquidation rewards.
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
    ) external;
}

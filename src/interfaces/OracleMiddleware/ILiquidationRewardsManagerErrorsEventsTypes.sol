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
     * @param gasPriceLimit Upper limit for the gas price
     * @param multiplierBps Multiplier for the liquidators
     */
    event RewardsParametersUpdated(
        uint32 gasUsedPerTick,
        uint32 otherGasUsed,
        uint32 rebaseGasUsed,
        uint32 rebalancerGasUsed,
        uint64 gasPriceLimit,
        uint32 multiplierBps
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
     * @param gasPriceLimit Upper limit for the gas price
     * @param multiplierBps Multiplier basis points for the liquidator rewards
     */
    struct RewardsParameters {
        uint32 gasUsedPerTick;
        uint32 otherGasUsed;
        uint32 rebaseGasUsed;
        uint32 rebalancerGasUsed;
        uint64 gasPriceLimit;
        uint32 multiplierBps;
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
     * @notice Indicates that the gasPriceLimit parameter has been set to a value we consider too high
     * @param value The wanted value
     */
    error LiquidationRewardsManagerGasPriceLimitTooHigh(uint256 value);

    /**
     * @notice Indicates that the multiplierBps parameter has been set to a value we consider too high
     * @param value The wanted value
     */
    error LiquidationRewardsManagerMultiplierBpsTooHigh(uint256 value);
}

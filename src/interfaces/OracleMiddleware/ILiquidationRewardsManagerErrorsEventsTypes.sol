// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

interface ILiquidationRewardsManagerErrorsEventsTypes {
    /* -------------------------------------------------------------------------- */
    /*                                   Events                                   */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice Emitted when the rewards parameters are changed.
     * @param gasUsedPerTick Gas used per tick to liquidate.
     * @param otherGasUsed Gas used for the rest of the computation.
     * @param gasPriceLimit Upper limit for the gas price.
     * @param multiplierBps Multiplier for the liquidators.
     */
    event RewardsParametersUpdated(
        uint32 gasUsedPerTick, uint32 otherGasUsed, uint64 gasPriceLimit, uint16 multiplierBps
    );

    /* -------------------------------------------------------------------------- */
    /*                                    Structs                                 */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice Parameters for the rewards calculation.
     * @param gasUsedPerTick Gas used per tick to liquidate.
     * @param otherGasUsed Gas used for the rest of the computation.
     * @param gasPriceLimit Upper limit for the gas price.
     * @param multiplierBps Multiplier basis points for the liquidator rewards.
     */
    struct RewardsParameters {
        uint32 gasUsedPerTick;
        uint32 otherGasUsed;
        uint64 gasPriceLimit;
        uint16 multiplierBps; // to be divided by REWARD_MULTIPLIER_DENOMINATOR
    }

    /* -------------------------------------------------------------------------- */
    /*                                   Errors                                   */
    /* -------------------------------------------------------------------------- */

    /// @dev Indicates that the gasUsedPerTick parameter has been set to a value we consider too high.
    error LiquidationRewardsManagerGasUsedPerTickTooHigh(uint256 value);
    /// @dev Indicates that the otherGasUsed parameter has been set to a value we consider too high.
    error LiquidationRewardsManagerOtherGasUsedTooHigh(uint256 value);
    /// @dev Indicates that the gasPriceLimit parameter has been set to a value we consider too high.
    error LiquidationRewardsManagerGasPriceLimitTooHigh(uint256 value);
    /// @dev Indicates that the multiplierBps parameter has been set to a value we consider too high.
    error LiquidationRewardsManagerMultiplierBpsTooHigh(uint256 value);
}

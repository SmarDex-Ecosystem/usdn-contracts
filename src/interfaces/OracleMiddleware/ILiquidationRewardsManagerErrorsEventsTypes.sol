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
     * @param multiplier Multiplier for the liquidators.
     */
    event RewardsParametersUpdated(uint32 gasUsedPerTick, uint32 otherGasUsed, uint64 gasPriceLimit, uint16 multiplier);

    /* -------------------------------------------------------------------------- */
    /*                                    Structs                                 */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice Parameters for the rewards calculation.
     * @param gasUsedPerTick Gas used per tick to liquidate.
     * @param otherGasUsed Gas used for the rest of the computation.
     * @param gasPriceLimit Upper limit for the gas price.
     * @param multiplier Multiplier for the liquidators.
     */
    struct RewardsParameters {
        uint32 gasUsedPerTick;
        uint32 otherGasUsed;
        uint64 gasPriceLimit;
        uint16 multiplier; // to be divided by REWARD_MULTIPLIER_DENOMINATOR
    }

    /* -------------------------------------------------------------------------- */
    /*                                   Errors                                   */
    /* -------------------------------------------------------------------------- */

    /// @dev Indicates that one of the rewards parameter has been set to a value we consider too high.
    error LiquidationRewardsManagerGasUsedPerTickTooHigh(uint256 value);
    /// @dev Indicates that one of the rewards parameter has been set to a value we consider too high.
    error LiquidationRewardsManagerOtherGasUsedTooHigh(uint256 value);
    /// @dev Indicates that one of the rewards parameter has been set to a value we consider too high.
    error LiquidationRewardsManagerGasPriceLimitTooHigh(uint256 value);
    /// @dev Indicates that one of the rewards parameter has been set to a value we consider too high.
    error LiquidationRewardsManagerMultiplierTooHigh(uint256 value);
}

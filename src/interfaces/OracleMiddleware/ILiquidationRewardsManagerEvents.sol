// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

interface ILiquidationRewardsManagerEvents {
    /**
     * @notice Emitted when the gas used per tick value is updated.
     * @param newGasUsedPerTick The new gas used per tick value.
     */
    event UpdateGasUsedPerTick(uint256 newGasUsedPerTick);

    /**
     * @notice Emitted when the base gas used value is updated.
     * @param newBaseGasUsed The new base gas used.
     */
    event UpdateBaseGasUsed(uint256 newBaseGasUsed);

    /**
     * @notice Emitted when the gas price limit is updated.
     * @param newGasPriceLimit The new gas price limit.
     */
    event UpdateGasPriceLimit(uint256 newGasPriceLimit);

    /**
     * @notice Emitted when the liquidation rewards multiplier is updated.
     * @param newRewardsMultiplier The new multiplier.
     */
    event UpdateRewardsMultiplier(uint16 newRewardsMultiplier);
}

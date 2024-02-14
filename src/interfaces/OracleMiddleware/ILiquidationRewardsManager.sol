// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import { ILiquidationRewardsManagerErrorsEventsTypes } from
    "src/interfaces/OracleMiddleware/ILiquidationRewardsManagerErrorsEventsTypes.sol";

interface ILiquidationRewardsManager is ILiquidationRewardsManagerErrorsEventsTypes {
    /**
     * @notice Returns the amount of wstETH that needs to be sent to the liquidator.
     * @param tickAmount The amount of tick to liquidate.
     * @param amountLiquidated The amount of collateral that got liquidated.
     * @return wstETHRewards_ The wstETH to send to the liquidator as rewards (in wei).
     */
    function getLiquidationRewards(uint16 tickAmount, uint256 amountLiquidated)
        external
        view
        returns (uint256 wstETHRewards_);

    /// @notice Returns the parameters used to calculate the rewards for a liquidation.
    function getRewardsParameters() external view returns (RewardsParameters memory);

    /**
     * @notice Set new parameters for the rewards calculation.
     * @param gasUsedPerTick Gas used per tick liquidated.
     * @param otherGasUsed Gas used for the rest of the computation.
     * @param gasPriceLimit Upper limit for the gas price.
     * @param multiplierBps Multiplier for the rewards (will be divided by REWARDS_MULTIPLIER_DENOMINATOR).
     */
    function setRewardsParameters(
        uint32 gasUsedPerTick,
        uint32 otherGasUsed,
        uint64 gasPriceLimit,
        uint16 multiplierBps
    ) external;
}

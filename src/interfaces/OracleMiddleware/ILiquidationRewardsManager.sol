// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.0;

import { ILiquidationRewardsManagerErrorsEventsTypes } from
    "src/interfaces/OracleMiddleware/ILiquidationRewardsManagerErrorsEventsTypes.sol";

interface ILiquidationRewardsManager is ILiquidationRewardsManagerErrorsEventsTypes {
    /* -------------------------------------------------------------------------- */
    /*                                  Constants                                 */
    /* -------------------------------------------------------------------------- */

    /// @notice Denominator for the reward multiplier, will give us a 0.01% basis point.
    function REWARDS_MULTIPLIER_DENOMINATOR() external pure returns (uint32);

    /**
     * @notice Fixed amount of gas a transaction consume.
     * @dev Is a uint256 to avoid overflows during gas usage calculations.
     */
    function BASE_GAS_COST() external pure returns (uint256);

    /* -------------------------------------------------------------------------- */
    /*                                  Getters Setters                           */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice Returns the amount of wstETH that needs to be sent to the liquidator.
     * @param tickAmount The amount of tick to liquidate.
     * @param remainingCollateral The amount of collateral remaining after liquidations. If negative, it means there was
     * not enough collateral to cover the losses caused by the liquidations (can happen during heavy price fluctuations)
     * @param rebased Whether an optional USDN rebase was performed.
     * @return wstETHRewards_ The wstETH to send to the liquidator as rewards (in wei).
     */
    function getLiquidationRewards(uint16 tickAmount, int256 remainingCollateral, bool rebased)
        external
        view
        returns (uint256 wstETHRewards_);

    /// @notice Returns the parameters used to calculate the rewards for a liquidation.
    function getRewardsParameters() external view returns (RewardsParameters memory);

    /**
     * @notice Set new parameters for the rewards calculation.
     * @param gasUsedPerTick Gas used per tick liquidated.
     * @param otherGasUsed Gas used by the rest of the computation.
     * @param rebaseGasUsed Gas used by the optional USDN rebase.
     * @param ordersGasUsedPerTick Gas used by the optional orders creation.
     * @param gasPriceLimit Upper limit for the gas price.
     * @param multiplierBps Multiplier for the rewards (will be divided by REWARDS_MULTIPLIER_DENOMINATOR).
     */
    function setRewardsParameters(
        uint32 gasUsedPerTick,
        uint32 otherGasUsed,
        uint32 rebaseGasUsed,
        uint32 ordersGasUsedPerTick,
        uint64 gasPriceLimit,
        uint32 multiplierBps
    ) external;
}

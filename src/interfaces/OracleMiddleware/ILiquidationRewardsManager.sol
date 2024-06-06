// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import { IBaseLiquidationRewardsManager } from "src/interfaces/OracleMiddleware/IBaseLiquidationRewardsManager.sol";
import { ILiquidationRewardsManagerErrorsEventsTypes } from
    "src/interfaces/OracleMiddleware/ILiquidationRewardsManagerErrorsEventsTypes.sol";

interface ILiquidationRewardsManager is IBaseLiquidationRewardsManager, ILiquidationRewardsManagerErrorsEventsTypes {
    /* -------------------------------------------------------------------------- */
    /*                                  Constants                                 */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice Denominator for the reward multiplier, will give us a 0.01% basis point
     * @return The BPS divisor
     */
    function BPS_DIVISOR() external pure returns (uint32);

    /**
     * @notice Fixed amount of gas a transaction consumes
     * @dev Is a uint256 to avoid overflows during gas usage calculations
     * @return The base gas cost
     */
    function BASE_GAS_COST() external pure returns (uint256);

    /* -------------------------------------------------------------------------- */
    /*                                  Getters Setters                           */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice Returns the parameters used to calculate the rewards for a liquidation
     * @return rewardsParameters_ The rewards parameters
     */
    function getRewardsParameters() external view returns (RewardsParameters memory);

    /**
     * @notice Set new parameters for the rewards calculation
     * @param gasUsedPerTick Gas used per tick liquidated
     * @param otherGasUsed Gas used for the rest of the computation
     * @param rebaseGasUsed Gas used for the optional USDN rebase
     * @param gasPriceLimit Upper limit for the gas price
     * @param multiplierBps Multiplier for the rewards (will be divided by BPS_DIVISOR)
     */
    function setRewardsParameters(
        uint32 gasUsedPerTick,
        uint32 otherGasUsed,
        uint32 rebaseGasUsed,
        uint64 gasPriceLimit,
        uint32 multiplierBps
    ) external;
}

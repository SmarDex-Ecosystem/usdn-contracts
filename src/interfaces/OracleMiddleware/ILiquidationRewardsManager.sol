// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import { ILiquidationRewardsManagerEvents } from "src/interfaces/OracleMiddleware/ILiquidationRewardsManagerEvents.sol";

interface ILiquidationRewardsManager is ILiquidationRewardsManagerEvents {
    /**
     * @notice Returns the amount of wstETH that needs to be sent to the liquidator.
     * @param tickAmount The amount of tick to liquidate .
     * @return _wstETHRewards The rewards in wei.
     */
    function getLiquidationRewards(uint16 tickAmount) external view returns (uint256 _wstETHRewards);
}

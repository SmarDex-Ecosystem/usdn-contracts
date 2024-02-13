// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

interface ILiquidationRewardsManager {
    /**
     * @notice Returns the amount of wstETH that needs to be sent to the liquidator.
     * @param tickAmount The amount of tick to liquidate.
     * @param amountLiquidated The amount of collateral that got liquidated.
     * @return _wstETHRewards The wstETH to send to the liquidator as rewards (in wei).
     */
    function getLiquidationRewards(uint16 tickAmount, uint256 amountLiquidated)
        external
        view
        returns (uint256 _wstETHRewards);
}

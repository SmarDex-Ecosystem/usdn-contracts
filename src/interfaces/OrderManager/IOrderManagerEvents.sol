// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.0;

interface IOrderManagerEvents {
    /**
     * @notice Emitted when a user deposit assets in a tick.
     * @param user The user that deposited the assets
     * @param amountInTick The amount of assets in the tick for that user
     * @param tick The desired tick to open the position in
     * @param tickVersion The version of the tick
     */
    event UserDepositedAssetsInTick(address indexed user, uint256 amountInTick, int24 tick, uint256 tickVersion);

    /**
     * @notice Emitted when a user withdraw assets from a tick.
     * @param user The owner of the removed assets
     * @param amountRemaining The amount remaining for that user in this tick
     * @param tick The tick the order was in
     * @param tickVersion The version of the tick
     */
    event UserWithdrewAssetsFromTick(address indexed user, uint256 amountRemaining, int24 tick, uint256 tickVersion);

    /**
     * @notice Emitted when the leverage of the orders has been updated.
     * @param newLeverage The new leverage
     */
    event OrdersLeverageUpdated(uint256 newLeverage);
}

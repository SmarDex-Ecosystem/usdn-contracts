// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.0;

interface IOrderManagerEvents {
    /**
     * @notice Emitted when an order is created.
     * @param user The user that created the order
     * @param amount The amount of assets in the order
     * @param tick The desired tick to open the position on
     * @param tickVersion The version of the tick
     */
    event OrderCreated(address indexed user, uint128 amount, int24 tick, uint256 tickVersion);

    /**
     * @notice Emitted when an order is removed.
     * @param user The owner of the removed order
     * @param tick The tick the order was on
     * @param tickVersion The version of the tick
     */
    event OrderRemoved(address indexed user, int24 tick, uint256 tickVersion);
}

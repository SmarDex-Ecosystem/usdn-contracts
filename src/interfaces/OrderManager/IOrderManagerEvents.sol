// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.0;

interface IOrderManagerEvents {
    /**
     * Emitted when assets are deposited in the contract
     * @param amount The amount of assets deposited
     * @param to The address the assets will be assigned to
     * @param positionVersion The version of the position those assets will be used in
     */
    event AssetsDeposited(uint256 amount, address to, uint256 positionVersion);

    /**
     * Emitted when pending assets are withdrawn from the contract
     * @param amount The amount of assets withdrawn
     * @param to The address the assets will be sent to
     */
    event PendingAssetsWithdrawn(uint256 amount, address to);
}

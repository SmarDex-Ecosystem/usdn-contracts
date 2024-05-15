// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.0;

interface IOrderManagerEvents {
    /**
     * @notice Emitted when the target imbalance on the long side has been updated
     * @param newTargetLongImbalance The new target long imbalance
     */
    event TargetLongImbalanceUpdated(int256 newTargetLongImbalance);

    /**
     * @notice Emitted when assets are deposited in the contract
     * @param amount The amount of assets deposited
     * @param to The address the assets will be assigned to
     * @param positionVersion The version of the position those assets will be used in
     */
    event AssetsDeposited(uint256 amount, address to, uint256 positionVersion);

    /**
     * @notice Emitted when pending assets are withdrawn from the contract
     * @param user The original owner of the position
     * @param amount The amount of assets withdrawn
     * @param to The address the assets will be sent to
     */
    event PendingAssetsWithdrawn(address user, uint256 amount, address to);
}

// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.0;

interface IRebalancerEvents {
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

    /**
     * @notice Emitted when the max leverage is updated
     * @param newMaxLeverage The new value for the max leverage
     */
    event PositionMaxLeverageUpdated(uint256 newMaxLeverage);

    /**
     * @notice Emitted when the minimum amount of assets to be deposited by a user is updated
     * @param minAssetDeposit The new minimum amount of assets to be deposited
     */
    event MinAssetDepositUpdated(uint256 minAssetDeposit);

    /**
     * @notice Emitted when the position version is updated
     * @param newPositionVersion The new version of the position
     */
    event PositionVersionUpdated(uint128 newPositionVersion);

    /**
     * @notice Emitted when the close imbalance limit in bps is updated
     * @param closeImbalanceLimitBps The new close imbalance limit in bps
     */
    event CloseImbalanceLimitBpsUpdated(uint256 closeImbalanceLimitBps);
}

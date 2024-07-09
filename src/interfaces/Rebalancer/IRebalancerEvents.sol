// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.0;

import { IUsdnProtocolTypes as Types } from "../../interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";

interface IRebalancerEvents {
    /**
     * @notice Emitted when a user initiates a deposit into the Rebalancer
     * @param payer The address of the user initiating the deposit
     * @param to The address the assets will be assigned to
     * @param amount The amount of assets deposited
     * @param timestamp The timestamp of the action
     */
    event InitiatedAssetsDeposit(address indexed payer, address indexed to, uint256 amount, uint256 timestamp);

    /**
     * @notice Emitted when assets are deposited in the contract
     * @param user The address of the user
     * @param amount The amount of assets deposited
     * @param positionVersion The version of the position those assets will be used in
     */
    event AssetsDeposited(address indexed user, uint256 amount, uint256 positionVersion);

    /**
     * @notice Emitted when a deposit failed due to the validation deadline elapsing and the user retrieves their funds
     * @param user The address of the user
     * @param amount The amount of assets that was refunded
     */
    event DepositRefunded(address indexed user, uint256 amount);

    /**
     * @notice Emitted when a user initiates the withdrawal of their pending assets
     * @param user The address of the user
     */
    event InitiatedAssetsWithdrawal(address indexed user);

    /**
     * @notice Emitted when pending assets are withdrawn from the contract
     * @param user The original owner of the position
     * @param to The address the assets will be sent to
     * @param amount The amount of assets withdrawn
     */
    event AssetsWithdrawn(address indexed user, address indexed to, uint256 amount);

    /**
     * @notice Emitted when the user initiates a close position action
     * through the rebalancer
     * @param user The rebalancer user
     * @param rebalancerAmountToClose The rebalancer amount to close
     * @param amountToClose The amount to close taking into account the previous versions' PnL
     * @param rebalancerAmountRemaining The remaining rebalancer assets of the user
     */
    event ClosePositionInitiated(
        address indexed user, uint256 rebalancerAmountToClose, uint256 amountToClose, uint256 rebalancerAmountRemaining
    );

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
     * @param entryAccMultiplier The accumulated multiplier at the opening of the new version
     * @param amount The amount of assets the rebalancer injected in the position as collateral
     * @param positionId The ID of the new position in the USDN protocol
     */
    event PositionVersionUpdated(
        uint128 newPositionVersion, uint256 entryAccMultiplier, uint128 amount, Types.PositionId positionId
    );

    /**
     * @notice Emitted when the close imbalance limit in bps is updated
     * @param closeImbalanceLimitBps The new close imbalance limit in bps
     */
    event CloseImbalanceLimitBpsUpdated(uint256 closeImbalanceLimitBps);

    /**
     * @notice Emitted when the time limits have been updated
     * @param validationDelay The new validation delay
     * @param validationDeadline The new validation deadline
     * @param actionCooldown The new action cooldown
     */
    event TimeLimitsUpdated(uint256 validationDelay, uint256 validationDeadline, uint256 actionCooldown);
}

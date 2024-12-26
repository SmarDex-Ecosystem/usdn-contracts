// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import { IUsdnProtocolTypes as Types } from "../../interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";

/**
 * @title Rebalancer Events
 * @notice Defines all custom events emitted by the Rebalancer contract.
 */
interface IRebalancerEvents {
    /**
     * @notice A user initiates a deposit into the Rebalancer.
     * @param payer The address of the user initiating the deposit.
     * @param to The address the assets will be assigned to.
     * @param amount The amount of assets deposited.
     * @param timestamp The timestamp of the action.
     */
    event InitiatedAssetsDeposit(address indexed payer, address indexed to, uint256 amount, uint256 timestamp);

    /**
     * @notice Assets are successfully deposited into the contract.
     * @param user The address of the user.
     * @param amount The amount of assets deposited.
     * @param positionVersion The version of the position where the assets will be used.
     */
    event AssetsDeposited(address indexed user, uint256 amount, uint256 positionVersion);

    /**
     * @notice A deposit fails due to the validation deadline elapsing, and the user retrieves their funds.
     * @param user The address of the user.
     * @param amount The amount of assets refunded.
     */
    event DepositRefunded(address indexed user, uint256 amount);

    /**
     * @notice A user initiates the withdrawal of their pending assets.
     * @param user The address of the user.
     */
    event InitiatedAssetsWithdrawal(address indexed user);

    /**
     * @notice Pending assets are withdrawn from the contract.
     * @param user The original owner of the position.
     * @param to The address the assets are sent to.
     * @param amount The amount of assets withdrawn.
     */
    event AssetsWithdrawn(address indexed user, address indexed to, uint256 amount);

    /**
     * @notice A user initiates a close position action through the rebalancer.
     * @param user The address of the rebalancer user.
     * @param rebalancerAmountToClose The amount of rebalancer assets to close.
     * @param amountToClose The amount to close, taking into account the previous versions PnL.
     * @param rebalancerAmountRemaining The remaining rebalancer assets of the user.
     */
    event ClosePositionInitiated(
        address indexed user, uint256 rebalancerAmountToClose, uint256 amountToClose, uint256 rebalancerAmountRemaining
    );

    /**
     * @notice The maximum leverage is updated.
     * @param newMaxLeverage The updated value for the maximum leverage.
     */
    event PositionMaxLeverageUpdated(uint256 newMaxLeverage);

    /**
     * @notice The minimum asset deposit requirement is updated.
     * @param minAssetDeposit The updated minimum amount of assets to be deposited by a user.
     */
    event MinAssetDepositUpdated(uint256 minAssetDeposit);

    /**
     * @notice The position version is updated.
     * @param newPositionVersion The updated version of the position.
     * @param entryAccMultiplier The accumulated multiplier at the opening of the new version.
     * @param amount The amount of assets injected into the position as collateral by the rebalancer.
     * @param positionId The ID of the new position in the USDN protocol.
     */
    event PositionVersionUpdated(
        uint128 newPositionVersion, uint256 entryAccMultiplier, uint128 amount, Types.PositionId positionId
    );

    /**
     * @notice Time limits are updated.
     * @param validationDelay The updated validation delay.
     * @param validationDeadline The updated validation deadline.
     * @param actionCooldown The updated action cooldown.
     * @param closeDelay The updated close delay.
     */
    event TimeLimitsUpdated(
        uint256 validationDelay, uint256 validationDeadline, uint256 actionCooldown, uint256 closeDelay
    );
}

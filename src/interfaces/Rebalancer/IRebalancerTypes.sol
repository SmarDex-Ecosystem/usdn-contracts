// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

/**
 * @title Rebalancer Types
 * @notice Defines all custom types used by the Rebalancer contract.
 */
interface IRebalancerTypes {
    /**
     * @notice Represents the deposit data of a user.
     * @dev A value of zero for `initiateTimestamp` indicates that the deposit or withdrawal has been validated.
     * @param initiateTimestamp The timestamp when the deposit or withdrawal was initiated.
     * @param amount The amount of assets deposited by the user.
     * @param entryPositionVersion The version of the position the user entered.
     */
    struct UserDeposit {
        uint40 initiateTimestamp;
        uint88 amount; // maximum 309'485'009 tokens with 18 decimals
        uint128 entryPositionVersion;
    }

    /**
     * @notice Represents data for a specific version of a position.
     * @dev The difference between `amount` here and the amount saved in the USDN protocol is the liquidation bonus.
     * @param amount The amount of assets used as collateral to open the position.
     * @param tick The tick of the position.
     * @param tickVersion The version of the tick.
     * @param index The index of the position in the tick list.
     * @param entryAccMultiplier The accumulated PnL multiplier of all positions up to this one.
     */
    struct PositionData {
        uint128 amount;
        int24 tick;
        uint256 tickVersion;
        uint256 index;
        uint256 entryAccMultiplier;
    }

    /**
     * @notice Defines parameters related to the validation process for rebalancer deposits and withdrawals.
     * @dev If `validationDeadline` has passed, the user must wait until the cooldown duration has elapsed. Then, for
     * deposit actions, the user must retrieve its funds using {IRebalancer.resetDepositAssets}. For withdrawal actions,
     * the user can simply initiate a new withdrawal.
     * @param validationDelay The minimum duration in seconds between an initiate action and the corresponding validate
     * action.
     * @param validationDeadline The maximum duration in seconds between an initiate action and the corresponding
     * validate action.
     * @param actionCooldown The duration in seconds from the initiate action during which the user can't interact with
     * the rebalancer if the `validationDeadline` is exceeded.
     * @param closeDelay The Duration in seconds from the last rebalancer long position opening during which the user
     * can't perform an {IRebalancer.initiateClosePosition}.
     */
    struct TimeLimits {
        uint64 validationDelay;
        uint64 validationDeadline;
        uint64 actionCooldown;
        uint64 closeDelay;
    }
}

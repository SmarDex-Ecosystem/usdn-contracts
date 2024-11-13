// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.0;

interface IRebalancerTypes {
    /**
     * @notice The deposit data of a user
     * @dev A value of zero for the `initiateTimestamp` indicates that the deposit or withdrawal was validated
     * @param initiateTimestamp Timestamp when the deposit or withdrawal was initiated
     * @param amount The amount of assets the user deposited
     * @param entryPositionVersion The position version the user entered at
     */
    struct UserDeposit {
        uint40 initiateTimestamp;
        uint88 amount; // Max 309'485'009 tokens with 18 decimals
        uint128 entryPositionVersion;
    }

    /**
     * @notice The data for a version of the position
     * @dev The difference between the amount here and the amount saved in the USDN protocol is the liquidation bonus
     * @param amount The amount of assets used as collateral to open the position
     * @param tick The tick of the position
     * @param tickVersion The version of the tick
     * @param index The index of the position in the tick list
     * @param entryAccMultiplier The accumulated PnL multiplier of all the positions up to this one
     */
    struct PositionData {
        uint128 amount;
        int24 tick;
        uint256 tickVersion;
        uint256 index;
        uint256 entryAccMultiplier;
    }

    /**
     * @notice The parameters related to the validation process of the Rebalancer deposit/withdraw
     * @dev If the `validationDeadline` has passed, the user is blocked from interacting until the cooldown duration
     * has elapsed (since the moment of the initiate action). After the cooldown, in case of a deposit action, the user
     * must withdraw their funds with `resetDepositAssets`. After the cooldown, in case of a withdrawal action, the user
     * can initiate a new withdrawal again
     * @param validationDelay Minimum duration in seconds between an initiate action and the corresponding validate
     * action
     * @param validationDeadline Maximum duration in seconds between an initiate action and the corresponding validate
     * action
     * @param actionCooldown Duration from the initiate action during which the user can't interact with the Rebalancer
     * if the `validationDeadline` elapsed.
     * @param closeDelay Duration from the last updatePosition during which the user can't perform a
     * {initiateClosePosition}
     */
    struct TimeLimits {
        uint64 validationDelay;
        uint64 validationDeadline;
        uint64 actionCooldown;
        uint64 closeDelay;
    }
}
